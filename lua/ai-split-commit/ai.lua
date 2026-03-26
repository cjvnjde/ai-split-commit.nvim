local M = {}

---------------------------------------------------------------------------
-- Prompt
---------------------------------------------------------------------------

local GROUPING_PROMPT = [[
Split the staged git changes below into semantic groups for review.

Requirements:
- Group related changes together by intent (feature, fix, refactor, docs, etc.).
- Prefer 1 to <max_group_count/> groups.
- Use all item IDs exactly once when possible.
- Each group must have:
  - title: short descriptive name for the group
  - criticality: one of "high", "medium", "low"
    - high: bug fixes, security patches, breaking changes, data loss risks
    - medium: new features, significant refactoring, behavior changes
    - low: docs, style, formatting, comments, minor cleanup, tests
  - item_ids: array of item IDs belonging to this group
- If an item does not fit anywhere, omit it.
- Return JSON only. No markdown fences. No commentary.

JSON schema:
{
  "groups": [
    {
      "title": "Fix auth token refresh",
      "criticality": "high",
      "item_ids": ["H1", "H2"]
    }
  ]
}

<extra_prompt/>

Recent commits:
<recent_commits/>

Items:
<items/>
]]

local GROUPING_SYSTEM = [[
You are an expert at reviewing staged git diffs and splitting them into semantic groups.
Return valid JSON only. Never wrap it in markdown fences.
Give each group a short, human-readable title (not a commit message).
Assign criticality based on the risk and importance of the changes.
Each item ID may appear in at most one group.
]]

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function escape_pattern(str)
  return (str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function fill_template(template, replacements)
  local result = template

  for placeholder, value in pairs(replacements) do
    result = result:gsub(escape_pattern(placeholder), ((value or ""):gsub("%%", "%%%%")))
  end

  return (result:gsub("<[%w_]+/>", ""))
end

local function extract_json(text)
  local first = text:find("{", 1, true)

  if not first then
    return nil
  end

  for i = #text, first, -1 do
    if text:sub(i, i) == "}" then
      return text:sub(first, i)
    end
  end

  return nil
end

local function strip_fences(text)
  local s = (text or ""):gsub("^%s*```[%w_-]*\n", ""):gsub("\n```%s*$", "")
  return ((s:gsub("^%s+", ""):gsub("%s+$", "")))
end

local function request_chat(config, prompt, system_prompt, label, callback)
  if config.debug then
    local dir = vim.fn.stdpath "cache" .. "/ai-split-commit-debug"
    vim.fn.mkdir(dir, "p")

    local f = io.open(string.format("%s/%s.txt", dir, os.date "%Y%m%d_%H%M%S"), "w")

    if f then
      f:write("=== SYSTEM ===\n" .. (system_prompt or "") .. "\n\n=== USER ===\n" .. (prompt or ""))
      f:close()
    end
  end

  local body = {
    model = config.model,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = prompt },
    },
  }

  if config.max_tokens then
    body.max_tokens = config.max_tokens
  end

  require("ai-provider").request({
    provider = config.provider,
    model = config.model,
    body = body,
    label = label,
  }, function(response, err)
    if err then
      return callback(nil, err)
    end

    if not response or response.status ~= 200 then
      return callback(nil, "HTTP error: " .. tostring(response and response.body or "unknown"))
    end

    local ok, data = pcall(vim.json.decode, response.body)

    if not ok or not data or not data.choices or not data.choices[1] or not data.choices[1].message then
      return callback(nil, "Invalid AI response")
    end

    callback(data.choices[1].message.content or "")
  end)
end

local function fallback_groups(repo)
  return {
    groups = {
      {
        title = "All staged changes",
        criticality = "medium",
        item_ids = vim.deepcopy(repo.item_order),
      },
    },
  }
end

local VALID_CRITICALITY = { high = true, medium = true, low = true }

local function normalize_criticality(value)
  local v = type(value) == "string" and value:lower() or ""
  return VALID_CRITICALITY[v] and v or "medium"
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function M.group_items(config, repo, extra_prompt, callback)
  local diff_mod = require "ai-split-commit.diff"
  local fake_session = { repo = repo }
  local parts = {}

  for _, item_id in ipairs(repo.item_order) do
    local item = repo.items_by_id[item_id]
    local patch = diff_mod.build_item_diff(fake_session, item_id)

    if config.max_item_diff_length and #patch > config.max_item_diff_length then
      patch = patch:sub(1, config.max_item_diff_length) .. "\n... (truncated)"
    end

    table.insert(parts, string.format("[%s] %s\n%s", item_id, item.path, patch))
  end

  local prompt = fill_template(config.grouping_prompt_template or GROUPING_PROMPT, {
    ["<extra_prompt/>"] = extra_prompt or "",
    ["<recent_commits/>"] = repo.recent_commits or "",
    ["<items/>"] = table.concat(parts, "\n\n"),
    ["<max_group_count/>"] = tostring(config.max_group_count or 8),
  })

  request_chat(config, prompt, config.grouping_system_prompt or GROUPING_SYSTEM, "AISplitCommit[grouping]", function(text, err)
    if err then
      return callback(fallback_groups(repo), err)
    end

    local json_text = extract_json(text or "")

    if not json_text then
      return callback(fallback_groups(repo), "AI did not return JSON")
    end

    local ok, data = pcall(vim.json.decode, json_text)

    if not ok or type(data) ~= "table" or type(data.groups) ~= "table" then
      return callback(fallback_groups(repo), "Failed to parse AI JSON")
    end

    local result = { groups = {} }

    for _, g in ipairs(data.groups) do
      if type(g) == "table" then
        local ids = {}

        for _, id in ipairs(g.item_ids or {}) do
          if type(id) == "string" then
            table.insert(ids, id)
          end
        end

        if #ids > 0 then
          table.insert(result.groups, {
            title = strip_fences(g.title or "Unnamed group"),
            criticality = normalize_criticality(g.criticality),
            item_ids = ids,
          })
        end
      end
    end

    if #result.groups == 0 then
      return callback(fallback_groups(repo), "AI returned no usable groups")
    end

    callback(result)
  end)
end

return M

local M = {}

M.config = {
  provider = "openrouter",
  model = "google/gemini-2.5-flash",
  max_tokens = 4096,
  max_item_diff_length = 1200,
  max_group_count = 8,
  debug = false,
  grouping_prompt_template = nil,
  grouping_system_prompt = nil,
}

M._active_session = nil
M._commands_registered = false

---------------------------------------------------------------------------
-- Model persistence
---------------------------------------------------------------------------

local function model_path()
  return vim.fn.stdpath "data" .. "/ai-split-commit/model_selection.json"
end

local function load_saved_model()
  local f = io.open(model_path(), "r")

  if not f then
    return nil
  end

  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()

  return (ok and data and data.provider and data.model) and data or nil
end

function M.save_model_selection()
  local path = model_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

  local f = io.open(path, "w")

  if f then
    f:write(vim.json.encode { provider = M.config.provider, model = M.config.model })
    f:close()
  end
end

function M.set_model(id)
  M.config.model = id
  M.save_model_selection()
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end

  if opts and opts.provider_config then
    require("ai-provider").setup { providers = opts.provider_config }
  end

  local saved = load_saved_model()

  if saved and saved.provider == M.config.provider then
    M.config.model = saved.model
  end

  M._register_commands()
end

---------------------------------------------------------------------------
-- Session lifecycle
---------------------------------------------------------------------------

function M.clear_active_session(session_id)
  if M._active_session and (not session_id or M._active_session.id == session_id) then
    M._active_session = nil
  end
end

function M.start(extra_prompt)
  if M._active_session and require("ai-split-commit.ui").is_alive(M._active_session) then
    return vim.notify("AISplitCommit session already open.", vim.log.levels.WARN)
  end

  local repo, err = require("ai-split-commit.git").collect_staged_state(M.config)

  if not repo then
    return vim.notify(err, vim.log.levels.ERROR)
  end

  require("ai-split-commit.ai").group_items(M.config, repo, extra_prompt, function(result, group_err)
    vim.schedule(function()
      local session = require("ai-split-commit.session").new(repo, result, extra_prompt)
      M._active_session = session
      require("ai-split-commit.ui").open(session)

      if group_err then
        vim.notify("AISplitCommit: fallback grouping: " .. group_err, vim.log.levels.WARN)
      end
    end)
  end)
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

function M._register_commands()
  if M._commands_registered then
    return
  end

  M._commands_registered = true

  vim.api.nvim_create_user_command("AISplitCommit", function(opts)
    M.start(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", desc = "Group staged changes for review" })

  vim.api.nvim_create_user_command("AISplitCommitModels", function(opts)
    local provider = opts.args ~= "" and opts.args or M.config.provider
    local models = require("ai-provider").get_models(provider)

    if #models == 0 then
      return vim.notify("No models for: " .. provider, vim.log.levels.WARN)
    end

    vim.ui.select(models, {
      prompt = "AISplitCommit models (" .. provider .. ")",
      format_item = function(m)
        return m.name .. " (" .. m.id .. ")" .. (m.id == M.config.model and " ●" or "")
      end,
    }, function(choice)
      if choice then
        M.set_model(choice.id)
        vim.notify("Model: " .. choice.name, vim.log.levels.INFO)
      end
    end)
  end, { nargs = "?", desc = "Select AI model" })

  vim.api.nvim_create_user_command("AISplitCommitLogin", function(opts)
    local provider = opts.args ~= "" and opts.args or M.config.provider
    require("ai-provider").login(provider)
  end, { nargs = "?", desc = "Authenticate AI provider" })

  vim.api.nvim_create_user_command("AISplitCommitLogout", function(opts)
    local provider = opts.args ~= "" and opts.args or M.config.provider
    require("ai-provider").logout(provider)
  end, { nargs = "?", desc = "Remove provider credentials" })

  vim.api.nvim_create_user_command("AISplitCommitStatus", function()
    local s = require("ai-provider").status(M.config.provider)
    vim.notify(
      string.format("%s: %s | Model: %s", s.provider, s.message, M.config.model),
      s.authenticated and vim.log.levels.INFO or vim.log.levels.WARN
    )
  end, { desc = "Show provider status" })
end

return M

local M = {}

local utils = require "ai-split-commit.utils"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function run(repo_root, args, input)
  local cmd = { "git" }

  if repo_root then
    vim.list_extend(cmd, { "-C", repo_root })
  end

  vim.list_extend(cmd, args)

  local output = vim.fn.system(cmd, input)
  return output, vim.v.shell_error
end

local function run_ok(repo_root, args, input)
  local _, code = run(repo_root, args, input)
  return code == 0
end

local function get_mode(repo_root, args)
  local output, code = run(repo_root, args)

  if code ~= 0 or utils.trim(output) == "" then
    return nil
  end

  return output:match "^(%d+)%s"
end

---------------------------------------------------------------------------
-- Collect staged state
---------------------------------------------------------------------------

function M.collect_staged_state(config)
  local root_out, root_code = run(nil, { "rev-parse", "--show-toplevel" })

  if root_code ~= 0 then
    return nil, "Not in a git repository."
  end

  local repo_root = utils.trim(root_out)

  local head_out, head_code = run(repo_root, { "rev-parse", "--verify", "HEAD" })
  local head = head_code == 0 and utils.trim(head_out) or nil

  if not run_ok(repo_root, { "diff", "--no-ext-diff", "--quiet" }) then
    return nil, "Unstaged changes found. Please stage everything first."
  end

  local untracked = utils.trim(run(repo_root, { "ls-files", "--others", "--exclude-standard" }))

  if untracked ~= "" then
    return nil, "Untracked files found. Stage or remove them first."
  end

  local diff_text, diff_code = run(repo_root, {
    "--no-pager", "diff", "--cached", "--no-color", "--no-ext-diff",
    "--no-renames", "--src-prefix=a/", "--dst-prefix=b/", "-U0",
  })

  if diff_code ~= 0 then
    return nil, "Failed to read staged diff."
  end

  if utils.trim(diff_text) == "" then
    return nil, "No staged changes found."
  end

  local parsed = require("ai-split-commit.diff").parse_unified_diff(diff_text)

  for _, path in ipairs(parsed.file_order) do
    local file = parsed.files_by_path[path]

    if file.is_binary then
      return nil, "Binary files not supported yet: " .. path
    end

    if file.has_no_newline_marker then
      return nil, "Missing-newline files not supported yet: " .. path
    end

    file.base_mode = file.base_exists and get_mode(repo_root, { "ls-tree", "HEAD", "--", path }) or nil
    file.final_mode = file.final_exists and get_mode(repo_root, { "ls-files", "--stage", "--", path }) or nil
    file.base_content = file.base_exists and select(1, run(repo_root, { "show", "HEAD:" .. path })) or nil
    file.final_content = file.final_exists and utils.read_file(repo_root .. "/" .. path) or nil
  end

  local commits_out, commits_code = run(repo_root, { "log", "--oneline", "-n", "5" })

  parsed.repo_root = repo_root
  parsed.head = head
  parsed.raw_diff = diff_text
  parsed.recent_commits = commits_code == 0 and utils.trim(commits_out) or "Initial repository (no previous commits)"
  parsed.config = config

  return parsed
end

---------------------------------------------------------------------------
-- Stage a single group
---------------------------------------------------------------------------

local function write_snapshot_to_index(repo_root, path, snapshot, file)
  if not snapshot.exists then
    return run_ok(repo_root, { "update-index", "--remove", "--", path })
        or nil, "Failed to remove " .. path .. " from index."
  end

  local sha_out, sha_code = run(repo_root, { "hash-object", "-w", "--stdin" }, snapshot.content or "")

  if sha_code ~= 0 then
    return nil, "Failed to write blob for " .. path
  end

  local sha = utils.trim(sha_out)
  local mode = snapshot.mode or file.final_mode or file.base_mode or "100644"

  return run_ok(repo_root, { "update-index", "--add", "--cacheinfo", mode .. "," .. sha .. "," .. path })
      or nil, "Failed to update index for " .. path
end

--- Stage only the given group's changes. Resets the index first.
--- On failure, restages everything so the user doesn't lose data.
function M.stage_group(session, group)
  local diff_mod = require "ai-split-commit.diff"
  local repo_root = session.repo.repo_root

  if not run_ok(repo_root, { "reset", "-q" }) then
    return nil, "Failed to reset index."
  end

  local selected_by_file = {}

  for _, item_id in ipairs(group.item_ids) do
    local item = session.repo.items_by_id[item_id]

    if item then
      selected_by_file[item.path] = selected_by_file[item.path] or {}
      selected_by_file[item.path][item_id] = true
    end
  end

  for path, selected in pairs(selected_by_file) do
    local file = session.repo.files_by_path[path]
    local snapshot, snap_err = diff_mod.build_file_snapshot(file, selected)

    if not snapshot then
      run(repo_root, { "add", "-A" })
      return nil, snap_err
    end

    local ok, idx_err = write_snapshot_to_index(repo_root, path, snapshot, file)

    if not ok then
      run(repo_root, { "add", "-A" })
      return nil, idx_err
    end
  end

  return true
end

return M

local M = {}

local utils = require "ai-split-commit.utils"

---------------------------------------------------------------------------
-- Patch building
---------------------------------------------------------------------------

local function count_selected(file, selected)
  local n = 0

  for _, id in ipairs(file.item_ids) do
    if selected[id] then
      n = n + 1
    end
  end

  return n
end

local function build_file_patch(file, selected)
  local n = count_selected(file, selected)

  if n == 0 then
    return nil
  end

  if file.synthetic_only then
    return table.concat(file.original_patch_lines, "\n") .. "\n"
  end

  local lines = { string.format("diff --git a/%s b/%s", file.path, file.path) }

  if not file.base_exists then
    table.insert(lines, "new file mode " .. (file.final_mode or "100644"))
  end

  table.insert(lines, file.base_exists and ("--- a/" .. file.path) or "--- /dev/null")

  local is_full_delete = file.base_exists and not file.final_exists and n == #file.item_ids
  table.insert(lines, is_full_delete and "+++ /dev/null" or ("+++ b/" .. file.path))

  for _, item_id in ipairs(file.item_ids) do
    if selected[item_id] then
      local item = file.items_by_id[item_id]

      if item and item.kind == "hunk" then
        vim.list_extend(lines, item.patch_lines)
      end
    end
  end

  return table.concat(lines, "\n") .. "\n"
end

local function build_patch_for_selection(repo, selected)
  local patches = {}

  for _, path in ipairs(repo.file_order) do
    local patch = build_file_patch(repo.files_by_path[path], selected)

    if patch and patch ~= "\n" then
      table.insert(patches, (patch:gsub("\n+$", "")))
    end
  end

  return table.concat(patches, "\n")
end

---------------------------------------------------------------------------
-- Diff parser
---------------------------------------------------------------------------

function M.parse_unified_diff(diff_text)
  local files = {}
  local file_order = {}
  local items_by_id = {}
  local item_order = {}
  local current_file, current_hunk = nil, nil
  local next_item = 0

  local function finalize_hunk()
    if current_file and current_hunk then
      table.insert(current_file.hunks, current_hunk)
      current_hunk = nil
    end
  end

  local function finalize_file()
    finalize_hunk()

    if not current_file then
      return
    end

    -- Determine canonical path
    local path
    if current_file.new_marker and current_file.new_marker ~= "/dev/null" then
      path = current_file.new_marker:gsub("^b/", "")
    elseif current_file.old_marker and current_file.old_marker ~= "/dev/null" then
      path = current_file.old_marker:gsub("^a/", "")
    else
      path = current_file.diff_new_path or current_file.diff_old_path
    end

    if not path then
      current_file = nil
      return
    end

    current_file.path = path
    current_file.base_exists = current_file.old_marker ~= "/dev/null"
    current_file.final_exists = current_file.new_marker ~= "/dev/null"
    current_file.items_by_id = {}
    current_file.item_ids = {}
    current_file.synthetic_only = #current_file.hunks == 0

    if current_file.synthetic_only then
      next_item = next_item + 1
      local id = "F" .. next_item
      local item = { id = id, kind = "file", path = path, label = "file-level change", patch_lines = {} }
      current_file.items_by_id[id] = item
      current_file.item_ids = { id }
      items_by_id[id] = item
      table.insert(item_order, id)
    else
      for _, hunk in ipairs(current_file.hunks) do
        next_item = next_item + 1
        local id = "H" .. next_item
        local item = { id = id, kind = "hunk", path = path, label = hunk.header, patch_lines = vim.deepcopy(hunk.lines) }
        current_file.items_by_id[id] = item
        table.insert(current_file.item_ids, id)
        items_by_id[id] = item
        table.insert(item_order, id)
      end
    end

    files[path] = current_file
    table.insert(file_order, path)
    current_file = nil
  end

  for _, line in ipairs(utils.split_lines(diff_text)) do
    if line:match "^diff %-%-git " then
      finalize_file()

      local old, new = line:match "^diff %-%-git a/(.+) b/(.+)$"
      current_file = {
        diff_old_path = old,
        diff_new_path = new,
        old_marker = old and ("a/" .. old) or nil,
        new_marker = new and ("b/" .. new) or nil,
        original_patch_lines = { line },
        hunks = {},
        is_binary = false,
        has_no_newline_marker = false,
      }
    elseif current_file then
      table.insert(current_file.original_patch_lines, line)

      if line:match "^Binary files " or line == "GIT binary patch" then
        current_file.is_binary = true
      elseif line == "\\ No newline at end of file" then
        current_file.has_no_newline_marker = true
        if current_hunk then
          table.insert(current_hunk.lines, line)
        end
      elseif line:match "^%-%-%- " then
        current_file.old_marker = line:match "^%-%-%-%s+(.+)$"
      elseif line:match "^%+%+%+ " then
        current_file.new_marker = line:match "^%+%+%+%s+(.+)$"
      elseif line:match "^@@ " then
        finalize_hunk()
        current_hunk = { header = line, lines = { line } }
      elseif current_hunk then
        table.insert(current_hunk.lines, line)
      end
    end
  end

  finalize_file()

  return {
    files_by_path = files,
    file_order = file_order,
    items_by_id = items_by_id,
    item_order = item_order,
  }
end

---------------------------------------------------------------------------
-- Public diff builders
---------------------------------------------------------------------------

function M.build_item_diff(session, item_id)
  if not session.repo.items_by_id[item_id] then
    return ""
  end

  return build_patch_for_selection(session.repo, { [item_id] = true })
end

function M.build_group_diff(session, group_id)
  local group = session.groups_by_id[group_id]

  if not group then
    return ""
  end

  return build_patch_for_selection(session.repo, utils.to_set(group.item_ids))
end

function M.build_all_preview(session)
  local S = require "ai-split-commit.session"
  local parts = {}

  for i, group in ipairs(S.get_ordered_groups(session)) do
    table.insert(parts, string.format("=== Group %d: [%s] %s ===", i, group.criticality, S.get_group_title(group)))

    if S.has_commit_message(group) then
      table.insert(parts, "")
      table.insert(parts, "Commit message:")
      vim.list_extend(parts, utils.split_lines(S.get_commit_message(group)))
    end

    table.insert(parts, "")
    vim.list_extend(parts, utils.split_lines(M.build_group_diff(session, group.id)))
    table.insert(parts, "")
  end

  return table.concat(parts, "\n")
end

---------------------------------------------------------------------------
-- Snapshot builder (for commit execution)
---------------------------------------------------------------------------

function M.build_file_snapshot(file, selected)
  local n = count_selected(file, selected)

  -- No hunks selected → base state
  if n == 0 then
    return { exists = file.base_exists, content = file.base_content, mode = file.base_mode or file.final_mode }
  end

  -- All hunks selected or synthetic → final state
  if file.synthetic_only or n == #file.item_ids then
    return { exists = file.final_exists, content = file.final_content, mode = file.final_mode or file.base_mode }
  end

  -- Partial selection → apply patch to base via temp dir
  local patch = build_file_patch(file, selected)

  if not patch then
    return nil, "Failed to build patch for " .. file.path
  end

  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")

  local file_path = tmp .. "/" .. file.path

  if file.base_exists and file.base_content then
    if not utils.write_file(file_path, file.base_content) then
      vim.fn.delete(tmp, "rf")
      return nil, "Failed to write base file for " .. file.path
    end
  end

  if not utils.write_file(tmp .. "/selection.patch", patch) then
    vim.fn.delete(tmp, "rf")
    return nil, "Failed to write patch for " .. file.path
  end

  local out = vim.fn.system { "git", "-C", tmp, "apply", "--unsafe-paths", "--whitespace=nowarn", "--unidiff-zero", tmp .. "/selection.patch" }

  if vim.v.shell_error ~= 0 then
    vim.fn.delete(tmp, "rf")
    return nil, string.format("Failed to build snapshot for %s: %s", file.path, (out:gsub("%s+$", "")))
  end

  local exists = vim.fn.filereadable(file_path) == 1
  local content = exists and utils.read_file(file_path) or nil
  vim.fn.delete(tmp, "rf")

  return { exists = exists, content = content, mode = exists and (file.final_mode or file.base_mode) or nil }
end

return M

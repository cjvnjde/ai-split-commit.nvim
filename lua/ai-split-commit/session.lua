local M = {}

local utils = require "ai-split-commit.utils"

local UNASSIGNED_ID = "__unassigned__"

local function make_group(session, opts)
  session.next_group_id = session.next_group_id + 1

  return {
    id = "g" .. session.next_group_id,
    kind = opts.kind or "normal",
    title = opts.title or "New group",
    criticality = opts.criticality or "medium",
    item_ids = opts.item_ids or {},
    stale = opts.stale or false,
  }
end

local function rebuild_indexes(session)
  session.groups_by_id = {}
  session.item_to_group = {}

  for _, group in ipairs(session.groups) do
    session.groups_by_id[group.id] = group

    for _, item_id in ipairs(group.item_ids) do
      session.item_to_group[item_id] = group.id
    end
  end
end

local function first_normal_group(session)
  for _, group in ipairs(session.groups) do
    if group.kind == "normal" then
      return group
    end
  end
end

local function mark_stale(group)
  if group and group.kind == "normal" then
    group.stale = true
  end
end

local CRITICALITY_RANK = {
  high = 3,
  medium = 2,
  low = 1,
}

local function sort_groups_by_criticality(groups)
  table.sort(groups, function(a, b)
    local a_rank = CRITICALITY_RANK[a.criticality] or 0
    local b_rank = CRITICALITY_RANK[b.criticality] or 0

    if a_rank ~= b_rank then
      return a_rank > b_rank
    end

    local a_id = tonumber((a.id or ""):match "^g(%d+)$") or 0
    local b_id = tonumber((b.id or ""):match "^g(%d+)$") or 0
    return a_id < b_id
  end)
end

local function build_groups_from_ai(session, ai_result)
  local assigned = {}

  for _, ai_group in ipairs((ai_result and ai_result.groups) or {}) do
    local item_ids = {}

    for _, item_id in ipairs(ai_group.item_ids or {}) do
      if session.repo.items_by_id[item_id] and not assigned[item_id] then
        table.insert(item_ids, item_id)
        assigned[item_id] = true
      end
    end

    if #item_ids > 0 then
      table.insert(session.groups, make_group(session, {
        title = ai_group.title or "Unnamed group",
        criticality = ai_group.criticality or "medium",
        item_ids = item_ids,
      }))
    end
  end

  if #session.groups == 0 then
    local all = vim.deepcopy(session.repo.item_order)

    table.insert(session.groups, make_group(session, {
      title = "All staged changes",
      item_ids = all,
    }))

    for _, id in ipairs(all) do
      assigned[id] = true
    end
  end

  sort_groups_by_criticality(session.groups)

  local unassigned = {}

  for _, id in ipairs(session.repo.item_order) do
    if not assigned[id] then
      table.insert(unassigned, id)
    end
  end

  table.insert(session.groups, {
    id = UNASSIGNED_ID,
    kind = "unassigned",
    title = "Unassigned",
    criticality = "low",
    item_ids = unassigned,
    stale = false,
  })

  rebuild_indexes(session)
end

local function select_first(session)
  local group = first_normal_group(session) or M.get_group(session, UNASSIGNED_ID)
  session.current_group_id = group and group.id or nil
  session.current_item_id = group and group.item_ids[1] or nil
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function M.get_group_title(group)
  if not group then
    return ""
  end

  local title = utils.trim(group.title or "")
  return title ~= "" and title or (group.kind == "unassigned" and "Unassigned" or "(unnamed)")
end

function M.get_group(session, group_id)
  return session.groups_by_id[group_id]
end

function M.get_group_index(session, group_id)
  for i, g in ipairs(session.groups) do
    if g.id == group_id then
      return i
    end
  end
end

function M.count_group_files(session, group_id)
  local group = M.get_group(session, group_id)

  if not group then
    return 0
  end

  local files = {}

  for _, item_id in ipairs(group.item_ids) do
    local item = session.repo.items_by_id[item_id]

    if item then
      files[item.path] = true
    end
  end

  return vim.tbl_count(files)
end

function M.rename_group(session, group_id, title)
  local group = M.get_group(session, group_id)

  if group and group.kind == "normal" then
    group.title = utils.trim(title or "")
    group.stale = false
  end
end

function M.new(repo, ai_result, extra_prompt)
  local session = {
    id = tostring(vim.loop.hrtime()),
    repo = repo,
    extra_prompt = extra_prompt,
    groups = {},
    groups_by_id = {},
    item_to_group = {},
    current_group_id = nil,
    current_item_id = nil,
    next_group_id = 0,
    unassigned_id = UNASSIGNED_ID,
    busy = false,
  }

  build_groups_from_ai(session, ai_result)
  select_first(session)

  return session
end

function M.apply_ai_groups(session, ai_result)
  session.groups = {}
  session.groups_by_id = {}
  session.item_to_group = {}
  session.next_group_id = 0

  build_groups_from_ai(session, ai_result)
  select_first(session)
end

function M.select_group(session, group_id)
  local group = M.get_group(session, group_id)

  if not group then
    return
  end

  session.current_group_id = group.id

  if not utils.list_contains(group.item_ids, session.current_item_id) then
    session.current_item_id = group.item_ids[1]
  end
end

function M.select_item(session, item_id)
  if not item_id or not session.repo.items_by_id[item_id] then
    return
  end

  session.current_item_id = item_id

  local owner = session.item_to_group[item_id]

  if owner then
    session.current_group_id = owner
  end
end

function M.add_group(session)
  local group = make_group(session, { title = "New group" })

  local pos = #session.groups + 1

  for i, g in ipairs(session.groups) do
    if g.kind == "unassigned" then
      pos = i
      break
    end
  end

  table.insert(session.groups, pos, group)
  rebuild_indexes(session)
  session.current_group_id = group.id
  session.current_item_id = nil

  return group
end

function M.move_item(session, item_id, target_group_id)
  local source_id = session.item_to_group[item_id]

  if not source_id or source_id == target_group_id then
    return false
  end

  local source = M.get_group(session, source_id)
  local target = M.get_group(session, target_group_id)

  if not source or not target then
    return false
  end

  utils.remove_value(source.item_ids, item_id)
  table.insert(target.item_ids, item_id)
  mark_stale(source)
  mark_stale(target)
  rebuild_indexes(session)

  session.current_group_id = target.id
  session.current_item_id = item_id

  return true
end

function M.move_item_to_new_group(session, item_id)
  local group = M.add_group(session)
  M.move_item(session, item_id, group.id)
  group.stale = false

  return group
end

function M.merge_groups(session, source_id, target_id)
  if source_id == target_id then
    return false
  end

  local source = M.get_group(session, source_id)
  local target = M.get_group(session, target_id)

  if not source or not target or source.kind ~= "normal" or target.kind ~= "normal" then
    return false
  end

  for _, id in ipairs(source.item_ids) do
    if not utils.list_contains(target.item_ids, id) then
      table.insert(target.item_ids, id)
    end
  end

  mark_stale(target)

  local idx = M.get_group_index(session, source_id)

  if idx then
    table.remove(session.groups, idx)
  end

  rebuild_indexes(session)
  session.current_group_id = target.id
  session.current_item_id = target.item_ids[1]

  return true
end

function M.delete_group(session, group_id)
  local group = M.get_group(session, group_id)
  local unassigned = M.get_group(session, UNASSIGNED_ID)

  if not group or not unassigned or group.kind ~= "normal" then
    return false
  end

  for _, id in ipairs(group.item_ids) do
    if not utils.list_contains(unassigned.item_ids, id) then
      table.insert(unassigned.item_ids, id)
    end
  end

  local idx = M.get_group_index(session, group_id)

  if idx then
    table.remove(session.groups, idx)
  end

  rebuild_indexes(session)
  select_first(session)

  return true
end

function M.reorder_group(session, group_id, direction)
  local idx = M.get_group_index(session, group_id)
  local group = idx and session.groups[idx]

  if not group or group.kind ~= "normal" then
    return false
  end

  local target_idx = direction == "up" and (idx - 1) or (idx + 1)
  local target = session.groups[target_idx]

  if not target or target.kind ~= "normal" then
    return false
  end

  session.groups[idx], session.groups[target_idx] = session.groups[target_idx], session.groups[idx]
  rebuild_indexes(session)

  return true
end

function M.get_ordered_groups(session)
  local result = {}

  for _, group in ipairs(session.groups) do
    if group.kind == "normal" and #group.item_ids > 0 then
      table.insert(result, group)
    end
  end

  return result
end

return M

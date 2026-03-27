local M = {}

local utils = require "ai-split-commit.utils"

local setup_diff_keymaps -- forward declaration, defined in Keymaps section

---------------------------------------------------------------------------
-- Buffer / window helpers
---------------------------------------------------------------------------

local function buf_valid(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function win_valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function init_buf(buf, ft, modifiable)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = modifiable
  vim.bo[buf].filetype = ft
end

local function set_buf_lines(buf, lines, modifiable)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = modifiable
end

local function configure_win(win)
  if not win_valid(win) then
    return
  end

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].wrap = false
  vim.wo[win].linebreak = false
end

local function focus(win)
  if win_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

local function line_for(map, value)
  for line, v in pairs(map or {}) do
    if v == value then
      return line
    end
  end

  return 1
end

local function map_buf(buf, lhs, fn, desc)
  vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, desc = desc })
end

local function normalize_view_mode(mode)
  return mode == "group_diff" and "group_diff" or "split"
end

local function current_focus_role(session)
  local current = vim.api.nvim_get_current_win()

  if session.ui.groups_win and current == session.ui.groups_win then
    return "groups"
  elseif session.ui.items_win and current == session.ui.items_win then
    return "items"
  elseif session.ui.diff_win and current == session.ui.diff_win then
    return "diff"
  elseif session.ui.message_win and current == session.ui.message_win then
    return "message"
  end

  return "groups"
end

local function focus_role(session, role)
  if role == "items" and win_valid(session.ui.items_win) then
    focus(session.ui.items_win)
  elseif role == "diff" and win_valid(session.ui.diff_win) then
    focus(session.ui.diff_win)
  elseif role == "message" and win_valid(session.ui.message_win) then
    focus(session.ui.message_win)
  elseif role == "groups" and win_valid(session.ui.groups_win) then
    focus(session.ui.groups_win)
  elseif win_valid(session.ui.diff_win) then
    focus(session.ui.diff_win)
  else
    focus(session.ui.groups_win)
  end
end

local function update_winbars(session)
  local view_label = session.ui.view_mode == "group_diff" and "group diff" or "split"

  pcall(function()
    vim.wo[session.ui.groups_win].winbar = " Groups  [gv " .. view_label .. " | a e M dd J/K R gc ga cc ca gs q]"
  end)

  if win_valid(session.ui.items_win) then
    pcall(function()
      vim.wo[session.ui.items_win].winbar = " Changes  [m n x]"
    end)
  end

  pcall(function()
    local title = session.ui.view_mode == "group_diff" and " Group Diff  [gv split | <CR> message]"
      or " Diff Preview  [gv group | <CR> message]"
    vim.wo[session.ui.diff_win].winbar = title
  end)

  pcall(function()
    vim.wo[session.ui.message_win].winbar = " Commit Message  [edit manually or use gc / ga]"
  end)
end

local function apply_layout(session)
  if not session.ui then
    return
  end

  local role = current_focus_role(session)

  if session.ui.view_mode == "group_diff" then
    if win_valid(session.ui.items_win) then
      pcall(vim.api.nvim_win_close, session.ui.items_win, true)
      session.ui.items_win = nil
    end
  else
    if not win_valid(session.ui.items_win) and win_valid(session.ui.groups_win) then
      focus(session.ui.groups_win)
      vim.cmd "vsplit"
      session.ui.items_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(session.ui.items_win, session.ui.items_buf)
      configure_win(session.ui.items_win)
    end
  end

  if win_valid(session.ui.groups_win) then
    vim.api.nvim_win_set_width(session.ui.groups_win, 34)
  end

  if win_valid(session.ui.items_win) then
    vim.api.nvim_win_set_width(session.ui.items_win, 42)
  end

  if win_valid(session.ui.message_win) then
    vim.api.nvim_win_set_height(session.ui.message_win, 9)
    vim.wo[session.ui.message_win].wrap = true
    vim.wo[session.ui.message_win].linebreak = true
  end

  update_winbars(session)

  if session.ui.view_mode == "group_diff" and role == "items" then
    role = "diff"
  end

  focus_role(session, role)
end

---------------------------------------------------------------------------
-- Highlights
---------------------------------------------------------------------------

local HL_HIGH = "AISplitCritHigh"
local HL_MEDIUM = "AISplitCritMedium"
local HL_LOW = "AISplitCritLow"
local HL_UNASSIGNED = "AISplitUnassigned"
local HL_STALE = "AISplitStale"
local HL_HAS_MESSAGE = "AISplitHasMessage"

local function setup_highlights()
  local function def(name, opts)
    if vim.fn.hlexists(name) == 0 or vim.api.nvim_get_hl(0, { name = name }) == nil then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end

  def(HL_HIGH, { fg = "#f38ba8", bold = true })
  def(HL_MEDIUM, { fg = "#f9e2af" })
  def(HL_LOW, { fg = "#a6e3a1" })
  def(HL_UNASSIGNED, { fg = "#6c7086", italic = true })
  def(HL_STALE, { fg = "#fab387", italic = true })
  def(HL_HAS_MESSAGE, { fg = "#89dceb", bold = true })
end

local CRIT_ICON = { high = "▲", medium = "●", low = "▽" }
local CRIT_HL = { high = HL_HIGH, medium = HL_MEDIUM, low = HL_LOW }
local NS = vim.api.nvim_create_namespace "ai_split_commit"

---------------------------------------------------------------------------
-- Session helpers
---------------------------------------------------------------------------

local function current_group(session)
  return require("ai-split-commit.session").get_group(session, session.current_group_id)
end

local function current_item(session)
  return session.current_item_id and session.repo.items_by_id[session.current_item_id] or nil
end

local function message_lines_to_text(lines)
  local filtered = {}

  for _, line in ipairs(lines or {}) do
    if not line:match "^#" then
      table.insert(filtered, line)
    end
  end

  while #filtered > 0 and filtered[#filtered] == "" do
    table.remove(filtered)
  end

  return table.concat(filtered, "\n")
end

local function save_current_message(session)
  if not session.ui or session.ui.skip_save then
    return
  end

  local group = current_group(session)

  if not group or group.kind ~= "normal" or not buf_valid(session.ui.message_buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(session.ui.message_buf, 0, -1, false)
  local message = message_lines_to_text(lines)
  require("ai-split-commit.session").save_group_commit_message_if_needed(session, group.id, message)
end

local function build_commit_extra_prompt(session, group, opts)
  opts = opts or {}
  local S = require "ai-split-commit.session"
  local parts = {
    "This commit message is for one already-grouped subset of changes.",
    "Follow the group topic closely in the subject and body.",
    "Do not mention unrelated changes from other groups.",
    "Group topic: " .. S.get_group_title(group),
    "Criticality: " .. tostring(group.criticality or "medium"),
  }

  if session.extra_prompt and utils.trim(session.extra_prompt) ~= "" then
    table.insert(parts, "Additional user guidance: " .. session.extra_prompt)
  end

  if opts.single then
    table.insert(parts, "Generate exactly one commit message only.")
    table.insert(parts, "Output only one message. Do not output alternatives or separator lines.")
  else
    table.insert(parts, "Generate commit messages only for this group, not the whole diff.")
  end

  return table.concat(parts, "\n")
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function render_groups(session)
  local S = require "ai-split-commit.session"
  local lines, map, highlights = {}, {}, {}

  for _, group in ipairs(session.groups) do
    local title = S.get_group_title(group)
    local files = S.count_group_files(session, group.id)
    local cursor = group.id == session.current_group_id and ">" or " "
    local line, hl

    if group.kind == "unassigned" then
      line = string.format("%s U %s  %di", cursor, title, #group.item_ids)
      hl = HL_UNASSIGNED
    else
      local icon = CRIT_ICON[group.criticality] or "●"
      local status = ""

      if S.has_commit_message(group) then
        status = group.stale and "[msg*]" or "[msg]"
      elseif group.stale then
        status = "[*]"
      end

      line = string.format("%s%s %s %s  %df %di", cursor, icon, title, status, files, #group.item_ids)
      hl = group.stale and HL_STALE or (CRIT_HL[group.criticality] or HL_MEDIUM)
    end

    table.insert(lines, line)
    map[#lines] = group.id
    highlights[#lines] = hl
  end

  if #lines == 0 then
    lines = { "(no groups)" }
  end

  session.ui.group_map = map
  set_buf_lines(session.ui.groups_buf, lines, false)
  vim.api.nvim_buf_clear_namespace(session.ui.groups_buf, NS, 0, -1)

  for ln, hl in pairs(highlights) do
    vim.api.nvim_buf_add_highlight(session.ui.groups_buf, NS, hl, ln - 1, 0, -1)
  end

  if win_valid(session.ui.groups_win) then
    vim.api.nvim_win_set_cursor(session.ui.groups_win, { line_for(map, session.current_group_id), 0 })
  end
end

local function render_items(session)
  local group = current_group(session)
  local lines, map = {}, {}

  if not group or #group.item_ids == 0 then
    lines = { "(no changes in this group)" }
    session.current_item_id = nil
  else
    local selected = utils.to_set(group.item_ids)
    local first = nil

    for _, path in ipairs(session.repo.file_order) do
      local file = session.repo.files_by_path[path]
      local ids = vim.tbl_filter(function(id)
        return selected[id]
      end, file.item_ids)

      if #ids > 0 then
        table.insert(lines, path)

        for _, id in ipairs(ids) do
          local item = session.repo.items_by_id[id]
          table.insert(lines, "  " .. id .. "  " .. item.label)
          map[#lines] = id
          first = first or id
        end

        table.insert(lines, "")
      end
    end

    if not session.current_item_id or not selected[session.current_item_id] then
      session.current_item_id = first
    end
  end

  session.ui.item_map = map
  set_buf_lines(session.ui.items_buf, lines, false)

  if win_valid(session.ui.items_win) then
    vim.api.nvim_win_set_cursor(session.ui.items_win, { line_for(map, session.current_item_id), 0 })
  end
end

local function render_diff_plain(session, text)
  if session.ui.diff_is_term then
    local old_buf = session.ui.diff_buf
    local new_buf = vim.api.nvim_create_buf(false, true)
    init_buf(new_buf, "diff", false)

    if win_valid(session.ui.diff_win) then
      vim.api.nvim_win_set_buf(session.ui.diff_win, new_buf)
      configure_win(session.ui.diff_win)
    end

    setup_diff_keymaps(session, new_buf)
    session.ui.diff_buf = new_buf
    session.ui.diff_is_term = false

    if buf_valid(old_buf) then
      pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
    end
  end

  local lines = utils.split_lines(text)
  set_buf_lines(session.ui.diff_buf, #lines > 0 and lines or { "(no diff)" }, false)
end

local function render_diff_with_delta(session, text)
  if session.ui.delta_job then
    pcall(vim.fn.jobstop, session.ui.delta_job)
    session.ui.delta_job = nil
  end

  session.ui.diff_render_id = (session.ui.diff_render_id or 0) + 1
  local render_id = session.ui.diff_render_id

  local old_buf = session.ui.diff_buf
  local new_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[new_buf].bufhidden = "wipe"

  local chan = vim.api.nvim_open_term(new_buf, {})

  if win_valid(session.ui.diff_win) then
    vim.api.nvim_win_set_buf(session.ui.diff_win, new_buf)
    configure_win(session.ui.diff_win)
  end

  setup_diff_keymaps(session, new_buf)
  session.ui.diff_buf = new_buf
  session.ui.diff_is_term = true

  if old_buf and old_buf ~= new_buf and buf_valid(old_buf) then
    pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
  end

  update_winbars(session)

  local width = win_valid(session.ui.diff_win)
      and vim.api.nvim_win_get_width(session.ui.diff_win)
    or 80

  local job = vim.fn.jobstart({ "delta", "--width=" .. tostring(width), "--paging=never" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      vim.schedule(function()
        if not session.ui or session.ui.diff_render_id ~= render_id then
          return
        end
        if not buf_valid(new_buf) then
          return
        end

        for i, line in ipairs(data) do
          if line ~= "" or i < #data then
            pcall(vim.api.nvim_chan_send, chan, line .. "\r\n")
          end
        end

        if win_valid(session.ui.diff_win) then
          pcall(vim.api.nvim_win_set_cursor, session.ui.diff_win, { 1, 0 })
        end
      end)
    end,
    on_exit = function(j)
      vim.schedule(function()
        if session.ui and session.ui.delta_job == j then
          session.ui.delta_job = nil
        end
      end)
    end,
  })

  if job <= 0 then
    render_diff_plain(session, text)
    return
  end

  session.ui.delta_job = job
  vim.fn.chansend(job, text)
  vim.fn.chanclose(job, "stdin")
end

local function use_delta()
  return require("ai-split-commit").config.use_delta ~= false and vim.fn.executable("delta") == 1
end

local function render_diff(session)
  local diff_mod = require "ai-split-commit.diff"
  local group = current_group(session)
  local text = ""

  if group then
    if session.ui.view_mode == "group_diff" then
      text = diff_mod.build_group_diff(session, group.id)
    elseif session.current_item_id and session.repo.items_by_id[session.current_item_id] then
      text = diff_mod.build_item_diff(session, session.current_item_id)
    else
      text = diff_mod.build_group_diff(session, group.id)
    end
  end

  if use_delta() and text ~= "" then
    render_diff_with_delta(session, text)
  else
    render_diff_plain(session, text)
  end
end

local function render_message(session)
  local S = require "ai-split-commit.session"
  local group = current_group(session)
  local lines = {}
  local modifiable = false

  if group and group.kind == "normal" then
    local message = S.get_commit_message(group)
    lines = utils.split_lines(message)

    if #lines == 0 then
      lines = {
        "# No commit message saved for this group.",
        "# Press gc to generate suggestions for the selected group.",
        "# Press ga to auto-generate one message for all groups.",
        "# Or type a commit message here manually.",
      }
    end

    modifiable = true
  else
    lines = {
      "# Unassigned changes cannot have a commit message.",
      "# Move them into a normal group first.",
    }
  end

  session.ui.skip_save = true
  set_buf_lines(session.ui.message_buf, lines, modifiable)
  session.ui.skip_save = false
end

local function render_all(session)
  if not M.is_alive(session) then
    return
  end

  local prev = session.ui.rendering
  session.ui.rendering = true
  render_groups(session)
  render_items(session)
  render_diff(session)
  render_message(session)
  session.ui.rendering = prev
end

---------------------------------------------------------------------------
-- Cursor tracking
---------------------------------------------------------------------------

local function on_group_cursor(session)
  if not M.is_alive(session) or session.ui.rendering then
    return
  end

  local line = vim.api.nvim_win_get_cursor(session.ui.groups_win)[1]
  local id = session.ui.group_map[line]

  if not id or id == session.current_group_id then
    return
  end

  save_current_message(session)
  require("ai-split-commit.session").select_group(session, id)
  render_all(session)
end

local function on_item_cursor(session)
  if not M.is_alive(session) or session.ui.rendering then
    return
  end

  local line = vim.api.nvim_win_get_cursor(session.ui.items_win)[1]
  local id = session.ui.item_map[line]

  if not id or id == session.current_item_id then
    return
  end

  require("ai-split-commit.session").select_item(session, id)
  render_diff(session)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local function pick_target_group(session, opts, callback)
  local S = require "ai-split-commit.session"
  local candidates = {}

  for _, group in ipairs(session.groups) do
    if group.id ~= opts.exclude and (opts.include_unassigned or group.kind == "normal") then
      table.insert(candidates, group)
    end
  end

  vim.ui.select(candidates, {
    prompt = opts.prompt,
    format_item = function(g)
      return S.get_group_title(g)
    end,
  }, function(choice)
    if choice then
      callback(choice.id)
    end
  end)
end

local function action_move_item(session)
  local item = current_item(session)

  if not item then
    vim.notify("Select an item first.", vim.log.levels.WARN)
    return
  end

  pick_target_group(session, {
    prompt = "Move item to group",
    include_unassigned = true,
    exclude = session.item_to_group[item.id],
  }, function(target_id)
    if require("ai-split-commit.session").move_item(session, item.id, target_id) then
      render_all(session)
    end
  end)
end

local function action_move_item_new(session)
  local item = current_item(session)

  if not item then
    vim.notify("Select an item first.", vim.log.levels.WARN)
    return
  end

  require("ai-split-commit.session").move_item_to_new_group(session, item.id)
  render_all(session)
end

local function action_unassign_item(session)
  local item = current_item(session)

  if not item then
    vim.notify("Select an item first.", vim.log.levels.WARN)
    return
  end

  if require("ai-split-commit.session").move_item(session, item.id, session.unassigned_id) then
    render_all(session)
  end
end

local function action_add_group(session)
  require("ai-split-commit.session").add_group(session)
  render_all(session)
  focus(session.ui.message_win)
end

local function action_rename_group(session)
  local group = current_group(session)

  if not group or group.kind ~= "normal" then
    vim.notify("Select a normal group first.", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Group name: ", default = group.title }, function(input)
    if input and utils.trim(input) ~= "" then
      require("ai-split-commit.session").rename_group(session, group.id, input)
      render_groups(session)
      render_message(session)
    end
  end)
end

local function action_merge_group(session)
  local group = current_group(session)

  if not group or group.kind ~= "normal" then
    vim.notify("Select a normal group first.", vim.log.levels.WARN)
    return
  end

  pick_target_group(session, {
    prompt = "Merge into",
    include_unassigned = false,
    exclude = group.id,
  }, function(target_id)
    if require("ai-split-commit.session").merge_groups(session, group.id, target_id) then
      render_all(session)
    end
  end)
end

local function action_delete_group(session)
  local group = current_group(session)

  if not group or group.kind ~= "normal" then
    vim.notify("Select a normal group first.", vim.log.levels.WARN)
    return
  end

  require("ai-split-commit.session").delete_group(session, group.id)
  render_all(session)
end

local function action_reorder(session, dir)
  local group = current_group(session)

  if not group or group.kind ~= "normal" then
    return
  end

  if require("ai-split-commit.session").reorder_group(session, group.id, dir) then
    render_all(session)
  end
end

local function action_regroup_all(session)
  save_current_message(session)
  session.busy = true

  local cfg = require("ai-split-commit").config

  require("ai-split-commit.ai").group_items(cfg, session.repo, session.extra_prompt, function(result, err)
    vim.schedule(function()
      session.busy = false

      if not M.is_alive(session) then
        return
      end

      require("ai-split-commit.session").apply_ai_groups(session, result)
      render_all(session)

      if err then
        vim.notify("AISplitCommit: fallback grouping: " .. err, vim.log.levels.WARN)
      end
    end)
  end)
end

local function action_preview_all(session)
  save_current_message(session)
  vim.cmd "tabnew"
  local buf = vim.api.nvim_get_current_buf()
  init_buf(buf, "diff", false)
  vim.api.nvim_buf_set_name(buf, "ai-split-commit://preview/" .. tostring(vim.loop.hrtime()))
  set_buf_lines(buf, utils.split_lines(require("ai-split-commit.diff").build_all_preview(session)), false)
end

local function action_toggle_view_mode(session)
  session.ui.view_mode = session.ui.view_mode == "split" and "group_diff" or "split"
  apply_layout(session)
  render_all(session)
end

local function action_generate_commit(session)
  save_current_message(session)
  local S = require "ai-split-commit.session"
  local group = current_group(session)

  if not group or group.kind ~= "normal" or #group.item_ids == 0 then
    vim.notify("Select a non-empty group first.", vim.log.levels.WARN)
    return
  end

  if session.busy then
    vim.notify("AISplitCommit is busy.", vim.log.levels.WARN)
    return
  end

  local ok, ai_commit = pcall(require, "ai-commit")

  if not ok or not ai_commit.generate_commit_for_diff then
    vim.notify("ai-commit.nvim is required for commit message generation.", vim.log.levels.ERROR)
    return
  end

  session.busy = true

  local diff_text = require("ai-split-commit.diff").build_group_diff(session, group.id)
  ai_commit.generate_commit_for_diff(diff_text, {
    extra_prompt = build_commit_extra_prompt(session, group),
    on_result = function(_, err)
      vim.schedule(function()
        session.busy = false
        if err then
          vim.notify("Failed to generate commit messages: " .. err, vim.log.levels.ERROR)
        end
      end)
    end,
    on_select = function(message)
      vim.schedule(function()
        if not M.is_alive(session) then
          return
        end

        S.set_group_commit_message(session, group.id, message, "ai")
        render_groups(session)
        render_message(session)
        vim.notify('Saved commit message for group "' .. S.get_group_title(group) .. '".', vim.log.levels.INFO)
      end)
    end,
  })
end

local function action_generate_all_commit_messages(session)
  save_current_message(session)
  local S = require "ai-split-commit.session"
  local groups = S.get_ordered_groups(session)

  if #groups == 0 then
    vim.notify("No groups available.", vim.log.levels.WARN)
    return
  end

  if session.busy then
    vim.notify("AISplitCommit is busy.", vim.log.levels.WARN)
    return
  end

  local ok, ai_commit = pcall(require, "ai-commit")

  if not ok or not ai_commit.generate_commit_messages_for_diff then
    vim.notify("ai-commit.nvim with batch API is required for auto generation.", vim.log.levels.ERROR)
    return
  end

  session.busy = true
  local index = 1
  local generated = 0
  local failed = 0

  local function step()
    if index > #groups then
      session.busy = false

      if M.is_alive(session) then
        render_all(session)
      end

      vim.notify(
        string.format("Auto-generated commit messages: %d ok, %d failed", generated, failed),
        failed == 0 and vim.log.levels.INFO or vim.log.levels.WARN
      )
      return
    end

    local group = groups[index]
    local diff_text = require("ai-split-commit.diff").build_group_diff(session, group.id)

    ai_commit.generate_commit_messages_for_diff(diff_text, {
      extra_prompt = build_commit_extra_prompt(session, group, {
        single = true,
      }),
    }, function(messages, err)
      vim.schedule(function()
        if not M.is_alive(session) then
          session.busy = false
          return
        end

        if messages and messages[1] then
          S.set_group_commit_message(session, group.id, messages[1], "ai")
          generated = generated + 1
        else
          failed = failed + 1
          if err then
            vim.notify(
              'Failed to generate commit message for "' .. S.get_group_title(group) .. '": ' .. err,
              vim.log.levels.WARN
            )
          end
        end

        if session.current_group_id == group.id then
          render_message(session)
        end
        render_groups(session)

        index = index + 1
        step()
      end)
    end)
  end

  step()
end

local function action_stage_group(session)
  save_current_message(session)
  local S = require "ai-split-commit.session"
  local group = current_group(session)

  if not group or group.kind ~= "normal" or #group.item_ids == 0 then
    vim.notify("Select a non-empty group first.", vim.log.levels.WARN)
    return
  end

  if session.busy then
    vim.notify("AISplitCommit is busy.", vim.log.levels.WARN)
    return
  end

  local ok, err = require("ai-split-commit.git").stage_group(session, group)

  if not ok then
    vim.notify("Failed to stage group: " .. err, vim.log.levels.ERROR)
    return
  end

  M.close(session)
  vim.notify('Staged group "' .. S.get_group_title(group) .. '". Run :AICommit or git commit.', vim.log.levels.INFO)
end

local function action_commit_saved_groups(session, current_only)
  save_current_message(session)
  local S = require "ai-split-commit.session"
  local groups = S.get_groups_with_commit_messages(session, { current_only = current_only })

  if #groups == 0 then
    vim.notify(
      current_only and "Current group has no saved commit message." or "No groups with saved commit messages.",
      vim.log.levels.WARN
    )
    return
  end

  if session.busy then
    vim.notify("AISplitCommit is busy.", vim.log.levels.WARN)
    return
  end

  session.busy = true
  local result, err = require("ai-split-commit.git").commit_groups(session, groups)
  session.busy = false

  if not result then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  M.close(session)
  vim.notify(
    string.format("Committed %d group(s). Run :AISplitCommit for remaining changes.", result.committed),
    vim.log.levels.INFO
  )
end

local function action_close(session)
  if session.busy then
    vim.notify("AISplitCommit is busy.", vim.log.levels.WARN)
    return
  end

  save_current_message(session)
  M.close(session)
end

---------------------------------------------------------------------------
-- Keymaps
---------------------------------------------------------------------------

local function setup_shared_keymaps(session, buf)
  map_buf(buf, "q", function() action_close(session) end, "Close")
  map_buf(buf, "P", function() action_preview_all(session) end, "Preview all")
  map_buf(buf, "gv", function() action_toggle_view_mode(session) end, "Toggle view mode")
  map_buf(buf, "gs", function() action_stage_group(session) end, "Stage group")
  map_buf(buf, "gc", function() action_generate_commit(session) end, "Generate commit message")
  map_buf(buf, "ga", function() action_generate_all_commit_messages(session) end, "Generate messages for all groups")
  map_buf(buf, "cc", function() action_commit_saved_groups(session, true) end, "Commit current group")
  map_buf(buf, "ca", function() action_commit_saved_groups(session, false) end, "Commit all groups with messages")
  map_buf(buf, "<Tab>", function() vim.cmd "wincmd w" end, "Next pane")
end

setup_diff_keymaps = function(session, buf)
  setup_shared_keymaps(session, buf)
  map_buf(buf, "<CR>", function() focus(session.ui.message_win) end, "Focus message")
end

local function setup_keymaps(session)
  local bufs = {
    session.ui.groups_buf,
    session.ui.items_buf,
    session.ui.diff_buf,
    session.ui.message_buf,
  }

  for _, buf in ipairs(bufs) do
    setup_shared_keymaps(session, buf)
  end

  local gb = session.ui.groups_buf
  map_buf(gb, "a", function() action_add_group(session) end, "Add group")
  map_buf(gb, "e", function() action_rename_group(session) end, "Rename group")
  map_buf(gb, "M", function() action_merge_group(session) end, "Merge group")
  map_buf(gb, "dd", function() action_delete_group(session) end, "Delete group")
  map_buf(gb, "J", function() action_reorder(session, "down") end, "Move down")
  map_buf(gb, "K", function() action_reorder(session, "up") end, "Move up")
  map_buf(gb, "R", function() action_regroup_all(session) end, "Regroup all")
  map_buf(gb, "<CR>", function()
    if session.ui.view_mode == "group_diff" then
      focus(session.ui.diff_win)
    else
      focus(session.ui.items_win)
    end
  end, "Focus next pane")

  local ib = session.ui.items_buf
  map_buf(ib, "m", function() action_move_item(session) end, "Move item")
  map_buf(ib, "n", function() action_move_item_new(session) end, "Move to new group")
  map_buf(ib, "x", function() action_unassign_item(session) end, "Unassign item")
  map_buf(ib, "<CR>", function() focus(session.ui.diff_win) end, "Focus diff")

  map_buf(session.ui.diff_buf, "<CR>", function() focus(session.ui.message_win) end, "Focus message")
end

---------------------------------------------------------------------------
-- Autocmds
---------------------------------------------------------------------------

local function setup_autocmds(session)
  local aug = vim.api.nvim_create_augroup("AISplitCommit_" .. session.id, { clear = true })
  session.ui.augroup = aug

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = aug,
    buffer = session.ui.groups_buf,
    callback = function()
      on_group_cursor(session)
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = aug,
    buffer = session.ui.items_buf,
    callback = function()
      on_item_cursor(session)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufLeave" }, {
    group = aug,
    buffer = session.ui.message_buf,
    callback = function()
      save_current_message(session)
      render_groups(session)
    end,
  })

  vim.api.nvim_create_autocmd("TabClosed", {
    group = aug,
    callback = function()
      if not M.is_alive(session) then
        require("ai-split-commit").clear_active_session(session.id)
      end
    end,
  })
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function M.is_alive(session)
  return session
    and session.ui
    and session.ui.tab
    and vim.api.nvim_tabpage_is_valid(session.ui.tab)
    and buf_valid(session.ui.groups_buf)
end

function M.open(session)
  setup_highlights()
  vim.cmd "tabnew"

  session.ui = {
    tab = vim.api.nvim_get_current_tabpage(),
    groups_buf = vim.api.nvim_create_buf(false, true),
    items_buf = vim.api.nvim_create_buf(false, true),
    diff_buf = vim.api.nvim_create_buf(false, true),
    message_buf = vim.api.nvim_create_buf(false, true),
    group_map = {},
    item_map = {},
    rendering = false,
    skip_save = false,
    view_mode = normalize_view_mode(require("ai-split-commit").config.default_view_mode),
    delta_job = nil,
    diff_render_id = 0,
    diff_is_term = false,
  }

  init_buf(session.ui.groups_buf, "aisplitcommit", false)
  init_buf(session.ui.items_buf, "aisplitcommit", false)
  init_buf(session.ui.diff_buf, "diff", false)
  init_buf(session.ui.message_buf, "gitcommit", true)

  vim.api.nvim_buf_set_name(session.ui.groups_buf, "ai-split-commit://groups/" .. session.id)
  vim.api.nvim_buf_set_name(session.ui.items_buf, "ai-split-commit://items/" .. session.id)
  vim.api.nvim_buf_set_name(session.ui.diff_buf, "ai-split-commit://diff/" .. session.id)
  vim.api.nvim_buf_set_name(session.ui.message_buf, "ai-split-commit://message/" .. session.id)

  vim.api.nvim_set_current_buf(session.ui.groups_buf)
  session.ui.groups_win = vim.api.nvim_get_current_win()

  vim.cmd "vsplit"
  session.ui.items_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(session.ui.items_win, session.ui.items_buf)

  vim.cmd "vsplit"
  session.ui.diff_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(session.ui.diff_win, session.ui.diff_buf)

  focus(session.ui.groups_win)
  vim.cmd "botright split"
  session.ui.message_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(session.ui.message_win, session.ui.message_buf)
  vim.cmd "wincmd J"

  configure_win(session.ui.groups_win)
  configure_win(session.ui.items_win)
  configure_win(session.ui.diff_win)
  configure_win(session.ui.message_win)

  apply_layout(session)
  setup_keymaps(session)
  setup_autocmds(session)
  render_all(session)
  focus(session.ui.groups_win)
end

function M.close(session)
  if not session or not session.ui then
    require("ai-split-commit").clear_active_session(session and session.id or nil)
    return
  end

  if session.ui.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, session.ui.augroup)
  end

  if session.ui.delta_job then
    pcall(vim.fn.jobstop, session.ui.delta_job)
    session.ui.delta_job = nil
  end

  local tab = session.ui.tab
  local buffers = {
    session.ui.groups_buf,
    session.ui.items_buf,
    session.ui.diff_buf,
    session.ui.message_buf,
  }

  if tab and vim.api.nvim_tabpage_is_valid(tab) then
    if vim.api.nvim_get_current_tabpage() ~= tab then
      vim.api.nvim_set_current_tabpage(tab)
    end

    vim.cmd "tabclose"
  end

  for _, buf in ipairs(buffers) do
    if buf_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  session.ui = nil
  require("ai-split-commit").clear_active_session(session.id)
end

return M

local M = {}

function M.trim(str)
  return ((str or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.split_lines(text)
  if not text or text == "" then
    return {}
  end

  return vim.split(text, "\n", { plain = true, trimempty = false })
end

function M.read_file(path)
  local file = io.open(path, "rb")

  if not file then
    return nil
  end

  local content = file:read "*a"
  file:close()
  return content
end

function M.write_file(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  local file = io.open(path, "wb")

  if not file then
    return false
  end

  file:write(content or "")
  file:close()
  return true
end

function M.list_contains(list, value)
  for _, item in ipairs(list or {}) do
    if item == value then
      return true
    end
  end

  return false
end

function M.remove_value(list, value)
  for i = #list, 1, -1 do
    if list[i] == value then
      table.remove(list, i)
    end
  end
end

function M.to_set(list)
  local set = {}

  for _, v in ipairs(list or {}) do
    set[v] = true
  end

  return set
end

function M.is_path_ignored(path, patterns)
  for _, pattern in ipairs(patterns or {}) do
    if path == pattern then
      return true
    end

    local regpat = vim.fn.glob2regpat(pattern)

    if path:match(regpat) then
      return true
    end
  end

  return false
end

return M

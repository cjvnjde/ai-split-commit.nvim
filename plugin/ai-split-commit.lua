if vim.g.loaded_ai_split_commit == 1 then
  return
end

vim.g.loaded_ai_split_commit = 1

require("ai-split-commit")._register_commands()

-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
local M = {}

M.open_tt = function()
  if vim.fn.executable("taskwarrior-tui") == 1 then
    local cmd = { "taskwarrior-tui" }
    local opts = {
      interactive = true,
      win = {
        style = "terminal",
        width = 0.9,
        height = 0.9,
        border = "rounded",
        title = "Taskwarrior-tui",
        title_pos = "center",
      },
    }
    Snacks.terminal(cmd, opts)
  end
end

return M

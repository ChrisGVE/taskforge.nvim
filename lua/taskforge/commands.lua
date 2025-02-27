-- User command definitions and dispatch
-- Handles :Taskforge commands and keymaps

local M = {}
local tasks = require("taskforge.tasks")
local picker = require("taskforge.picker")
local dashboard = require("taskforge.dashboard")

function M.register()
  vim.api.nvim_create_user_command("Taskforge", function(opts)
    local subcmd = opts.fargs[1]
    if subcmd == "dashboard" then
      dashboard.toggle()
    elseif subcmd == "config" then
      tasks.configure()
    elseif subcmd == "pick" then
      picker.open_task_picker()
    end
  end, {
    nargs = "+",
    complete = function()
      return { "dashboard", "pick", "create", "done", "refresh" }
    end,
  })

  -- Example keymaps (configurable)
  vim.keymap.set("n", "<leader>ft", "<cmd>Taskforge pick<cr>", { desc = "Find tasks" })
end

return M

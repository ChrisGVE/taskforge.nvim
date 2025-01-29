local M = {}

local Result = require("taskforge.utils.result")
local Utils = require("taskforge.utils.utils")

function M.check()
  local has_taskwarrior = vim.fn.executable("task") == 1
  local has_taskwarrior_tui = vim.fn.executable("taskwarrior-tui") == 1

  vim.health.start("Taskforge Health Check")

  -- Check for TaskWarrior dependency
  if has_taskwarrior then
    vim.health.ok("TaskWarrior is installed and available.")
  else
    vim.health.error("TaskWarrior is not installed. Install it to use this plugin.")
  end

  -- Check for Taskwarrior configuration
  if has_taskwarrior then
    local taskrc = Utils.get_taskrc()
    if taskrc then
      vim.health.ok("TaskWarrior configuration file found.")
    else
      vim.health.warn("TaskWarrior configuration file not found.")
    end
  end

  -- Check for Taskwarrior-tui dependency
  if has_taskwarrior_tui then
    vim.health.ok("Taskwarrior-tui is installed and available.")
  else
    vim.health.warn("Taskwarrior-tui is not installed.")
  end

  -- Check if necessary Neovim features exist
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim version is compatible.")
  else
    vim.health.warn("Neovim 0.10 or higher is recommended for best compatibility.")
  end

  -- Check if plugin has been initialized properly
  if _G.Taskforge_init then
    vim.health.ok("Plugin has been initialized correctly.")
  else
    vim.health.warn("Plugin may not have initialized correctly.")
  end
end

return M

local M = {}

local utils = require("taskforge.utils.utils")
local debug = require("taskforge.utils.debug")

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
    local cmd = "task"
    local opts = { separators = { "\n", " " } }

    local confirmation = utils.exec(cmd, { "_get", "rc.confirmation" }, opts) --[[@as Taskforge.utils.Result]]
    local verbose = utils.exec(cmd, { "_get", "rc.verbose" }, opts) --[[@as Taskforge.utils.Result]]
    local editor = utils.exec(cmd, { "_get", "rc.editor" }, opts) --[[@as Taskforge.utils.Result]]

    log(confirmation)
    log(verbose)
    log(editor)

    local nok = false

    if confirmation == nil or confirmation.err or confirmation.value.stdout ~= "off" then
      vim.health.warn("TaskWarrior configuration.confirmation is on. This may cause unexpected behavior.")
      nok = true
    else
      vim.health.ok("TaskWarrior configuration.confirmation is on.")
    end
    if verbose == nil or verbose.err or (verbose.value.stdout ~= "no" and verbose.value.stdout ~= "nothing") then
      vim.health.warn("TaskWarrior configuration.verbose is on. This may cause unexpected behavior.")
      nok = true
    else
      vim.health.ok("TaskWarrior configuration.verbose is on.")
    end
    if editor == nil or editor.err or (editor.value.stdout == "" and editor.value.stdout ~= "nvim") then
      vim.health.warn("TaskWarrior configuration.editor is not set to neovim. This may cause unexpected behavior.")
      nok = true
    else
      vim.health.ok("TaskWarrior configuration.editor is set to neovim.")
    end
    if nok then
      vim.health.warn("Please consider running `:Taskforge taskwarrior_config` to address these configuration issues.")
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

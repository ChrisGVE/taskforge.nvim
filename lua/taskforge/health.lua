local M = {}

local exec = require("taskforge.utils.exec")
local cache = require("taskforge.utils.config")

function M.check()
  vim.health.start("Taskforge Health Check")

  -- Check if necessary Neovim features exist
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim version is compatible.")
  else
    vim.health.warn("Neovim 0.10 or higher is recommended for best compatibility.")
  end

  -- Check for TaskWarrior dependency
  if cache.has_taskwarrior then
    vim.health.ok("TaskWarrior is installed and available.")
    if cache.data_file_exists then
      vim.health.ok("Taskwarrior's database exists and readable.")
    else
      vim.health.error("Taskwarrior's database does not exist. Taskwarrior has not been setup yet.")
    end
  else
    vim.health.error("TaskWarrior is not installed. Install it to use this plugin.")
  end

  -- Check for Taskwarrior configuration
  if cache.has_taskwarrior then
    -- fetch the taskwarrior options
    local cmd = "task"
    local opts = { separators = { "\n", " " } }

    local confirmation = exec.exec(cmd, { "_get", "rc.confirmation" }, opts) --[[@as Taskforge.utils.Result]]
    local verbose = exec.exec(cmd, { "_get", "rc.verbose" }, opts) --[[@as Taskforge.utils.Result]]
    local editor = exec.exec(cmd, { "_get", "rc.editor" }, opts) --[[@as Taskforge.utils.Result]]

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
      vim.health.warn(
        "\nPlease consider running `:Taskforge taskwarrior_config` to address these configuration issues.\n"
      )
    end
  end

  -- Check for TaskOpen dependency
  if cache.has_taskopen then
    vim.health.ok("TaskOpen is installed and available.")
  else
    vim.health.error("TaskOpen is not installed.")
  end

  -- Check for Taskwarrior-tui dependency
  if cache.has_taskwarrior_tui then
    vim.health.ok("Taskwarrior-tui is installed and available.")
  else
    vim.health.warn("Taskwarrior-tui is not installed.")
  end

  -- Check if plugin has been initialized properly
  if cache.valid then
    vim.health.ok("Plugin has been initialized correctly.")
  else
    vim.health.warn("Plugin may not have initialized correctly.")
  end
end

return M

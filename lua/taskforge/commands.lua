-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--

-- local config = require('session_manager.config')
-- local AutoloadMode = require('session_manager.config').AutoloadMode
-- local utils = require('session_manager.utils')
-- local Job = require('plenary.job')
local markdown = require("taskforge.markdown")
local interface = require("taskforge.interface")
local utils = require("taskforge.utils.utils")
local commands = {}

-- Displays action selection menu for :SessionManager
function commands.available_commands()
  local cmds = {}
  for cmd, _ in pairs(commands) do
    if cmd ~= "available_commands" then
      table.insert(cmds, cmd)
    end
  end
  vim.ui.select(cmds, {
    prompt = "Task Forge",
    format_item = function(item)
      return item:sub(1, 1):upper() .. item:sub(2):gsub("_", " ")
    end,
  }, function(item)
    if item then
      commands[item]()
    end
  end)
end

-- create a markdown file or insert the tasks in the current markdown buffer
function commands.markdown()
  vim.api.nvim_create_user_command("Taskforge.markdown", function(opts)
    markdown.render_markdown_todos(unpack(opts.fargs))
  end, { nargs = "*" })
end

-- configure taskwarrior
function commands.taskwarrior_config()
  local cmd = "task"
  utils.exec(cmd, { "config", "verbose", "no" })
  utils.exec(cmd, { "config", "confirmation", "off" })
  utils.exec(cmd, { "config", "editor", "nvim" })
end

-- toggle autotracking of tags for the current project
function commands.toggle_tracking()
  -- local last_session = utils.get_last_session_filename()
  -- if last_session then
  --   utils.load_session(last_session, discard_current)
  --   return true
  -- end
  -- return false
end

-- check if all is good for TaskForge
function commands.checkhealth()
  -- local cwd = vim.uv.cwd()
  -- if cwd then
  --   local session = config.dir_to_session_filename(cwd)
  --   if session:exists() then
  --     utils.load_session(session.filename, discard_current)
  --     return true
  --   end
  -- end
  -- return false
end

-- Instantiate taskwarrior-tui
function commands.taskwarrior_tui()
  interface.open_tt()
end

-- Launch the interface to manage all tasks
function commands.tasks()
  -- local cwd = vim.uv.cwd()
  -- if cwd then
  --   local session = config.dir_to_session_filename(cwd)
  --   return session:exists()
  -- end
  -- return false
end

-- Launch the interface to manage all tasks related to the current project
function commands.project()
  -- local job = Job:new({
  --   command = 'git',
  --   args = { 'rev-parse', '--show-toplevel' },
  -- })
  -- job:sync()
  -- local git_dir = job:result()[1]
  -- if git_dir then
  --   local session = config.dir_to_session_filename(git_dir)
  --   if session:exists() then
  --     utils.load_session(session.filename, discard_current)
  --     return true
  --   end
  -- end
  -- return false
end

-- Manually refresh the task cache  for the current project
function commands.refresh_cache()
  -- local cwd = vim.uv.cwd()
  -- if cwd then
  --   utils.save_session(config.dir_to_session_filename(cwd).filename)
  -- end
end

-- local autoloaders = {
--   [AutoloadMode.Disabled] = function() return true end,
--   [AutoloadMode.CurrentDir] = commands.load_current_dir_session,
--   [AutoloadMode.LastSession] = commands.load_last_session,
--   [AutoloadMode.GitSession] = commands.load_git_session,
-- }

--- Loads a session based on settings. Executed after starting the editor.
-- function commands.autoload_session()
--   if vim.fn.argc() > 0 or vim.g.started_with_stdin then
--     return
--   end
--
--   local modes = config.autoload_mode
--   if not vim.isarray(config.autoload_mode) then
--     modes = { config.autoload_mode }
--   end
--
--   for _, mode in ipairs(modes) do
--     if autoloaders[mode]() then
--       return
--     end
--   end
-- end

-- create a new task based on the current tag in the current project
function commands.create()
  -- local sessions = utils.get_sessions()
  -- vim.ui.select(sessions, {
  --   prompt = 'Delete Session',
  --   format_item = function(item) return utils.shorten_path(item.dir) end,
  -- }, function(item)
  --   if item then
  --     utils.delete_session(item.filename)
  --     commands.delete_session()
  --   end
  -- end)
end

-- mark the task linked to the current tag as done
function commands.done()
  -- local cwd = vim.uv.cwd()
  -- if cwd then
  --   local session = config.dir_to_session_filename(cwd)
  --   if session:exists() then
  --     utils.delete_session(session.filename)
  --   end
  -- end
end

-- Toggle the confirmation for creation/done tasks
function commands.toggle_confirmation() end

-- Toggle the autorefresh of the task cache for the current project
function commands.toggle_autorefresh() end

return commands

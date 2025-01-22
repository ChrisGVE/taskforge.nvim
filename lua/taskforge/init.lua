-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License


-- Core modules
local M = {}

-- Module imports
local tasks = require("taskforge.interface")
-- local tag_tracker = require("taskforge.tag_tracker") -- not implemented yet
local interface = require("taskforge.interface")
local dashboard = require("taskforge.dashboard")
local utils = require("taskforge.utils.utils")
local markdown = require("taskforge.markdown")
local debug = require("taskforge.utils.debug")
local project = require("taskforge.project")
local config = require("taskforge.config")

local api = vim.api
local fn = vim.fn

local debug_flg = false

--- Debugging global hooks 
---@param show? boolean
_G.dd = function(show, ...)
  if debug_flg then
    debug.inspect(show, ...)
  end
end

---@param show? boolean
---@param msg? string|string[]
---@param opts? snacks.notify.Opts
_G.bt = function(show, msg,opts)
  if debug_flg then
    debug.backtrace(show, msg, opts)
  end
end

_G.log = function(...)
  if debug_flg then
    debug.log(...)
  end
end

---@param show? boolean
_G.metrics = function(show)
  if debug_flg then
    debug.metrics(show)
  end
end

---@param fn fun()
---@param opts? {count?: number, flush?: boolean, title?: string, show?: boolean}
_G.profile = function(fn, opts)
  if debug_flg then
    debug.profile(fn, opts)
  end
end

---@param opts? {min?: number, show?:boolean}
---@return {summary:table<string, snacks.debug.Stat>, trace:snacks.debug.Stat[], traces:snacks.debug.Trace[]}
_G.stats = function(opts)
  if debug_flg then
    return debug.stats(opts)
  else
    return {}
  end
end

---@param name string?
_G.trace = function(name)
  if debug_flg then
    return debug.trace(name)
  end
end

---@param modname string
---@param mod? table
---@param suffix? string
_G.tracemod = function(modname, mod, suffix)
  if debug_flg then
    return debug.tracemod(modname, mod, suffix)
  end
end

M.project = nil

-- Command registration
function M.create_commands()
	-- api.nvim_create_user_command("TaskForge", function(opts)
	-- 	interface.toggle()
	-- end, {})
	--
	-- api.nvim_create_user_command("TaskForgeAdd", function(opts)
	-- 	interface.add_task(opts.args)
	-- end, { nargs = "*" })
end

-- Autocommand setup for tag tracking
-- function M.create_autocommands()
-- 	local group = api.nvim_create_augroup("TaskForge", { clear = true })
--
-- 	api.nvim_create_autocmd({ "BufEnter" }, {
-- 		group = group,
-- 		callback = function()
-- 			if utils.is_filetype_enabled() then
-- 				tag_tracker.scan_buffer()
-- 			end
-- 		end,
-- 	})
--
-- 	-- Debounced tag tracking
-- 	local timer = nil
-- 	api.nvim_create_autocmd({ "TextChanged", "TextChanged" }, {
-- 		group = group,
-- 		callback = function()
-- 			if utils.is_filetype_enabled() then
-- 				if timer then
-- 					timer:stop()
-- 				end
-- 				timer = vim.defer_fn(function()
-- 					tag_tracker.update_buffer()
-- 				end, 500) -- 500ms debounce
-- 			end
-- 		end,
-- 	})
-- end

-- return the task section for dashboard.nvim
function M.get_dashboard_tasks()
	return dashboard.get_tasks()
end

-- return the task section for Snacks.nvim dashboard
function M.get_snacks_dashboard_tasks()
  log()
	return dashboard.get_snacks_dashboard_tasks()
end

-- Core setup function
---Setting utlis, tasks and dashboard
---@param options table?
function M.setup(options)
  config.setup(options)

  -- Setup modules
  debug_flg = debug.setup(config.options.debug)
  interface.setup()
  dashboard.setup()
  markdown.setup()

  -- Setup the autocommands around the project
  project.setup()

  log()
  -- if options then
  --   log("User config: ", options)
  -- else
  --   log("No user config")
  -- end

  M.project = project.get_project_name()
  log("Project: ", M.project)

	-- Set up commands
	M.create_commands()

	-- Set up autocommands for tag tracking
	-- M.create_autocommands()
end

return M

-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License

-- Core modules
local M = {}

-- Module imports
local interface = require("taskforge.interface")
local tag_tracker = require("taskforge.tag-tracker")
local tasks = require("taskforge.tasks")
local dashboard = require("taskforge.dashboard")
local project = require("taskforge.project")
local config = require("taskforge.utils.config")
local cache = require("taskforge.utils.cache")

--- Debugging global hooks
local has_debug = package["snacks.debug"] ~= nil
local debug = nil
if has_debug then
  debug = require("snacks.debug")
end

-- Show a notification with a pretty printed dump of the object(s)
-- with lua treesitter highlighting and the location of the caller
_G.dd = function(...)
  if debug and config.debug.enable then
    debug.inspect(...)
  end
end

-- Show a notification with a pretty backtrace
---@param msg? string|string[]
---@param opts? snacks.notify.Opts
_G.bt = function(msg, opts)
  if debug and config.debug.enable then
    debug.backtrace(msg, opts)
  end
end

--- Run the current buffer or a range of lines.
--- Shows the output of `print` inlined with the code.
--- Any error will be shown as a diagnostic.
---@param opts? {name?:string, buf?:number, print?:boolean}
_G.run = function(opts)
  if debug and config.debug.enable then
    debug.run(opts)
  end
end

-- Log a message to the file `./debug.log`.
-- - a timestamp will be added to every message.
-- - accepts multiple arguments and pretty prints them.
-- - if the argument is not a string, it will be printed using `vim.inspect`.
-- - if the message is smaller than 120 characters, it will be printed on a single line.
--
-- ```lua
-- Snacks.debug.log("Hello", { foo = "bar" }, 42)
-- -- 2024-11-08 08:56:52 Hello { foo = "bar" } 42
-- ```
_G.log = function(...)
  if config.debug.enable then
    local file = config.debug.log_file or "./debug.log"
    local fd = io.open(file, "a+")
    if not fd then
      error(("Could not open file %s for writing"):format(file))
    end
    local c = select("#", ...)
    local parts = {} ---@type string[]
    for i = 1, c do
      local v = select(i, ...)
      parts[i] = type(v) == "string" and v or vim.inspect(v)
    end
    local max_length = config.debug.log_max_len or 120
    local msg = table.concat(parts, " ")
    msg = #msg < max_length and msg:gsub("%s+", " ") or msg
    fd:write(os.date("%Y-%m-%d %H:%M:%S ") .. msg)
    fd:write("\n")
    fd:close()
  end
end

_G.metrics = function()
  if debug and config.debug.enable then
    debug.metrics()
  end
end

-- Very simple function to profile a lua function.
-- * **flush**: set to `true` to use `jit.flush` in every iteration.
-- * **count**: defaults to 100
---@param fn fun()
---@param opts? {count?: number, flush?: boolean, title?: string}
_G.profile = function(fn, opts)
  if debug and config.debug.enable then
    debug.profile(fn, opts)
  end
end

---@param opts? {min?: number, show?:boolean}
---@return {summary:table<string, snacks.debug.Stat>, trace:snacks.debug.Stat[], traces:snacks.debug.Trace[]}
_G.stats = function(opts)
  if debug and config.debug.enable then
    return debug.stats(opts)
  else
    return {}
  end
end

---@param name string?
_G.trace = function(name)
  if debug and config.debug.enable then
    return debug.trace(name)
  end
end

---@param modname string
---@param mod? table
---@param suffix? string
_G.tracemod = function(modname, mod, suffix)
  if debug and config.debug.enable then
    return debug.tracemod(modname, mod, suffix)
  end
end

M.project = nil

-- Autocommand setup for tag tracking
-- function M.create_autocommands()
-- 	local group = api.nvim_create_augroup("Taskforge", { clear = true })
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
  if cache.valid then
    return dashboard.get_dashboard_tasks()
  else
    return {}
  end
end

-- return the task section for Snacks.nvim dashboard
function M.get_snacks_dashboard_tasks()
  if cache.valid then
    return dashboard.get_snacks_dashboard_tasks()
  else
    return {}
  end
end

-- Core setup function
---Setting utlis, tasks and dashboard
---@param options table?
function M.setup(options)
  config:setup(options)
  cache:setup()

  if cache.valid then
    local subcommands = require("taskforge.subcommands")
    vim.api.nvim_create_user_command(
      "Taskforge",
      subcommands.run,
      { nargs = 1, bang = true, complete = subcommands.complete, desc = "Run Task Forge command" }
    )

    --
    tasks.setup()
    dashboard.setup()
    project.setup()
    interface.setup()
    tag_tracker.setup()

    M.project = project.get_project_name()
    -- log("Project: ", M.project)

    -- Set up autocommands
    -- M.create_autocommands()
  else
    vim.notify("Taskforge disabled, use `checkhealth taskforge` for diagnostic.")
  end
end

return M

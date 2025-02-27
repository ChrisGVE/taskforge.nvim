# taskforge.nvim/lua//taskforge/
taskforge.nvim/lua//taskforge//commands.lua
```lua
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
```

taskforge.nvim/lua//taskforge//dashboard.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
local M = {}

local utils = require("taskforge.utils.utils")
local tasks = require("taskforge.tasks")
local project = require("taskforge.project")
local config = require("taskforge.utils.config")
local cache = require("taskforge.utils.cache")
local interface = require("taskforge.interface")
local events = require("taskforge.utils.events")

local project_tasks = {}
local other_tasks = {}

local function parse_task(task_to_parse, columnsWidth)
  local task = {}
  for _, column in ipairs(config.dashboard.format.columns) do
    local sl = " "
    if _ == 1 then
      sl = ""
    end
    local width = columnsWidth[column]
    local value = tostring(task_to_parse[column] or "")
    if column == "project" and value ~= "" then
      value = "[" .. value .. "]"
    end
    value = utils.clip_text(value, width)
    if column == "urgency" then
      table.insert(task, sl .. utils.align_right(value, width))
    else
      table.insert(task, sl .. utils.align_left(value, width))
    end
  end
  return table.concat(task, "")
end

local function sanitize_tasks(task_list)
  for _, task in ipairs(task_list) do
    for k, v in pairs(task) do
      if v ~= nil then
        if k == "urgency" then
          task[k] = string.format("%.2f", v)
        elseif k == "due" then
          -- log("[" .. task["id"] .. "]" .. "due (v): " .. v)
          local current_year = os.date("%Y")
          local pattern = "^" .. current_year .. "%-(.*)"
          local date_string = tostring(utils.get_os_date(v, "%Y-%m-%d"))
          local new_date_string = date_string:match(pattern)
          task[k] = new_date_string or date_string
        elseif k == "project" then
          task[k] = utils.replace_project_name(v, config.dashboard.format)
        end
      else
        task[k] = ""
      end
    end
  end
end

local function get_columns_width(task_list, other_tasks, maxwidth)
  -- log()
  local columnsWidth = {}
  -- TODO: Check if this is really necessary, also it should be independent from whether we target snacks.nvim or dashboard.nvim
  local max_width = maxwidth or config.dashboard.format.max_width
  local needed_for_padding = #config.dashboard.format.columns
  local total_width = 0
  sanitize_tasks(task_list)
  sanitize_tasks(other_tasks)
  for _, column in ipairs(config.dashboard.format.columns) do
    columnsWidth[column] = 0
    for _, task in ipairs(task_list) do
      if task[column] ~= nil then
        -- task = sanitize_task(task)
        columnsWidth[column] = math.max(columnsWidth[column], utils.utf8len(tostring(task[column])))
      end
    end
    for _, task in ipairs(other_tasks) do
      if task[column] ~= nil then
        -- task = sanitize_task(task)
        columnsWidth[column] = math.max(columnsWidth[column], utils.utf8len(tostring(task[column])))
      end
    end
    total_width = total_width + columnsWidth[column]
  end
  if columnsWidth["project"] ~= nil then
    columnsWidth["project"] = columnsWidth["project"] + 2
  end
  if columnsWidth["description"] ~= nil then
    local delta = (max_width - total_width) - needed_for_padding
    columnsWidth["description"] = columnsWidth["description"] + delta
  end
  return columnsWidth
end

function M.get_tasks()
  local project_tasks = tasks.get_dashboard_tasks(config.dashboard.format.limit, M.project)
  local other_tasks = {}
  if
    M.project ~= nil
    and config.dashboard.format.non_project_limit ~= nil
    and config.dashboard.format.non_project_limit > 0
  then
    other_tasks = tasks.get_dashboard_tasks(config.dashboard.format.non_project_limit, M.project, true)
  end
  return project_tasks, other_tasks
end

function M.get_dashboard_tasks()
  local dashboard_tasks = {}
  tasks = M.get_tasks()
  if tasks ~= nil then
    for _, t in ipairs(tasks) do
      table.insert(dashboard_tasks, t)
    end
  end
  return dashboard_tasks
end

function M.format_tasks(max_width)
  local lines = {}
  local task_list, other_tasks = M.get_tasks()
  local columnsWidth = get_columns_width(task_list, other_tasks, max_width)

  for _, task in ipairs(task_list) do
    local line = parse_task(task, columnsWidth)
    if
      task.urgency ~= nil
      and config.highlights.urgent.threshold ~= nil
      and tonumber(task.urgency) >= config.highlights.urgent.threshold
    then
      table.insert(project_tasks, line)
    else
      table.insert(other_tasks, line)
    end
    table.insert(lines, line)
  end

  if #other_tasks > 0 and M.project and #task_list > 0 then
    table.insert(lines, "--+--")
  end

  for _, task in ipairs(other_tasks) do
    local line = parse_task(task, columnsWidth)
    if
      task.urgency ~= nil
      and config.highlights.urgent.threshold ~= nil
      and tonumber(task.urgency) >= config.highlights.urgent.threshold
    then
      table.insert(project_tasks, line)
    else
      table.insert(other_tasks, line)
    end
    table.insert(lines, line)
  end
  return lines
end

function M.process_tasks_for_snacks()
  local max_width = config.dashboard.format.max_width - config.dashboard.snacks_options.indent
  local hl_normal = "dir"
  local hl_overdue = "special"
  local lines = {}
  local task_list, other_tasks = M.get_tasks()
  local columnsWidth = get_columns_width(task_list, other_tasks, max_width)

  if M.project ~= nil then
    table.insert(lines, { M.project, hl = hl_normal, width = max_width - 1, align = "center" })
    table.insert(lines, { "\n", hl = hl_normal })
  end

  for _, task in ipairs(task_list) do
    local line = parse_task(task, columnsWidth)
    local hl = hl_normal
    if
      task.urgency ~= nil
      and config.highlights.urgent.threshold ~= nil
      and tonumber(task.urgency) >= config.highlights.urgent.threshold
    then
      table.insert(project_tasks, line)
      hl = hl_overdue
    else
      table.insert(other_tasks, line)
    end
    table.insert(lines, { line .. "\n", hl = hl })
  end

  if #other_tasks > 0 and M.project and #task_list > 0 then
    table.insert(lines, { "--+--", hl = hl_normal, width = max_width - 1, align = "center" })
    table.insert(lines, { "\n", hl = hl_normal })
  end

  for _, task in ipairs(other_tasks) do
    local line = parse_task(task, columnsWidth)
    local hl = hl_normal
    if
      task.urgency ~= nil
      and config.highlights.urgent.threshold ~= nil
      and tonumber(task.urgency) >= config.highlights.urgent.threshold
    then
      table.insert(project_tasks, line)
      hl = hl_overdue
    else
      table.insert(other_tasks, line)
    end
    table.insert(lines, { line .. "\n", hl = hl })
  end

  return lines
end

--- Gets default highlight groups
--- @param which string (urgent|not_urgent) group name
--- @return table hl Highlight definition
local function get_default_hl_group(which)
  if which == "urgent" then
    local hl = vim.api.nvim_get_hl(0, { name = "@keyword" })
    return {
      bg = hl.bg,
      fg = hl.fg,
      cterm = hl.cterm,
      bold = hl.bold,
      italic = hl.italic,
      reverse = hl.reverse,
    }
  elseif which == "not_urgent" then
    local hl = vim.api.nvim_get_hl(0, { name = "Comment" })
    return {
      bg = hl.bg,
      fg = hl.fg,
      cterm = hl.cterm,
      bold = hl.bold,
      italic = hl.italic,
      reverse = hl.reverse,
    }
  else
    return {
      italic = true,
    }
  end
end

local function setup_hl_groups()
  local hl_urgent = nil
  if config.highlights and config.highlights.urgent and config.highlights.urgent.group then
    hl_urgent = config.highlights.urgent.group
  else
    hl_urgent = get_default_hl_group("urgent")
  end
  if hl_urgent then
    vim.api.nvim_set_hl(0, "TFDashboardHeaderUrgent", hl_urgent)
  end
  local hl_not_urgent = nil

  if config.highlights and config.highlights.normal and config.highlights.normal.group then
    hl_not_urgent = config.highlights.normal.group
  else
    hl_not_urgent = get_default_hl_group("not_urgent")
  end
  if hl_not_urgent then
    vim.api.nvim_set_hl(0, "TFDashboardHeader", hl_not_urgent)
  end
end

local function hl_tasks()
  setup_hl_groups()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  -- log()
  log("Lines: " .. vim.inspect(project_tasks))
  for i, line in ipairs(lines) do
    if utils.in_table(project_tasks, line) then
      vim.api.nvim_buf_add_highlight(0, -1, "TFDashboardHeaderUrgent", i - 1, 0, -1)
    elseif utils.in_table(other_tasks, line) then
      vim.api.nvim_buf_add_highlight(0, -1, "TFDashboardHeader", i - 1, 0, -1)
    end
  end
end

function M.get_snacks_dashboard_tasks()
  -- log()
  local title = {
    icon = config.dashboard.snacks_options.icon,
    title = config.dashboard.snacks_options.title,
    pane = config.dashboard.snacks_options.pane or 1,
  }
  if config.dashboard.snacks_options.key ~= nil and config.dashboard.snacks_options.action ~= nil then
    if config.dashboard.snacks_options.action == "taskwarrior-tui" and cache.has_taskwarrior_tui then
      title.action = function()
        interface.open_tt()
      end
    elseif config.dashboard.snacks_options.action == "project" then
      title.action = function()
        -- TODO: hook the project view
      end
    elseif config.dashboard.snacks_options.action == "tasks" then
      title.action = function()
        -- TODO: hook the overall view
      end
    end
    if title.action then
      title.key = config.dashboard.snacks_options.key
    end
  end
  local section = {
    pane = config.dashboard.snacks_options.pane or 1,
    padding = config.dashboard.snacks_options.padding,
    indent = config.dashboard.snacks_options.indent,
    text = M.process_tasks_for_snacks(),
  }
  section.height = config.dashboard.snacks_options.height
      and math.max(config.dashboard.snacks_options.height, #section.text)
    or #section.text

  -- setup autocmd to catch Snacks.Dashboard events, for reference here they are:
  --  SnacksDashboardOpened
  --  SnacksDashboardClosed
  --  SnacksDashboardUpdatePre
  --  SnacksDashboardUpdatePost
  --  SncaksDashboardUpdate

  vim.api.nvim_create_autocmd("User", {
    pattern = "SnacksDashboardLoaded",
    callback = hl_tasks,
  })
  return { title, section }
end

function M.setup()
  -- log()
  M.project = project.get_project_name()
  -- log("Project: ", M.project)
  --
end

return M
```

taskforge.nvim/lua//taskforge//health.lua
```lua
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
```

taskforge.nvim/lua//taskforge//init.lua
```lua
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

  cache.valid = false -- temporary disabling the plugin

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
```

taskforge.nvim/lua//taskforge//interface.lua
```lua
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

function M.setup() end

return M
```

taskforge.nvim/lua//taskforge//markdown.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
-- MIT License
local M = {}

-- local main_ui = require("taskforge.main-ui")
-- local tag_tracker = require("taskforge.tag-tracker") -- not implemented yet
local tasks = require("taskforge.tasks")
local api = vim.api

function M.get_markdown_todos(project, group_by, limit)
  local todos = tasks.get_todo(project, group_by, limit) or {}
  local todos_lines = {}
  for _, todo in ipairs(todos) do
    table.insert(todos_lines, string.rep(" ", todo.indent * 2) .. "- [ ] " .. todo.task.description)
  end
  return todos_lines
end

function M.render_markdown_todos(project, group_by, limit)
  local todos_lines = M.get_markdown_todos(project, group_by, limit)
  local row, col = unpack(api.nvim_win_get_cursor(0))
  api.nvim_buf_set_lines(0, row, row, true, todos_lines)
  api.nvim_win_set_cursor(0, { row + #todos_lines, col })
end

return M
```

taskforge.nvim/lua//taskforge//project.lua
```lua
-- Credit for the inspiration of this module goos to Ahmedkhalf
-- https://github.com/ahmedkhalf/project.nvim

local M = {}

local utils = require("taskforge.utils.utils")
local glob = require("taskforge.utils.globtopattern")
local config = require("taskforge.utils.config")
local uv = vim.loop
local api = vim.api
local fn = vim.fn

M.attached_lsp = false

-- Get the lsp client for the current buffer
---@return string|nil error
function M.find_lsp_root()
  local buf_ft = api.nvim_get_option_value("filetype", {})
  local clients = vim.lsp.get_clients()

  -- log(buf_ft, clients)

  if next(clients) == nil then
    return nil
  end

  for _, client in pairs(clients) do
    local filetypes = client.config.filetypes
    if filetypes and vim.tbl_contains(filetypes, buf_ft) then
      return client.config.root_dir
    end
  end

  return nil
end

function M.set_pwd(dir)
  if dir ~= nil then
    if fn.getcwd() ~= dir then
      api.nvim_set_current_dir(dir)
    end
    return true
  end

  return false
end

function M.is_excluded(dir)
  if config.project.root_patterns.exclude_dirs == nil then
    return false
  end
  for _, dir_pattern in ipairs(config.project.root_patterns.exclude_dirs) do
    if dir:match(dir_pattern) ~= nil then
      return true
    end
  end

  return false
end

function M.exists(path_name)
  return vim.fn.empty(vim.fn.glob(path_name)) == 0
end

---@return string|nil,string|nil, string|nil
function M.find_pattern_root()
  local search_dir = fn.expand("%:p:h", true)
  if fn.has("win32") > 0 then
    search_dir = search_dir:gsub("\\", "/")
  end

  -- log("search dir:", search_dir)

  local last_dir_cache = ""
  local curr_dir_cache = {}

  local function get_parent(path_name)
    path_name = path_name:match("^(.*)/")
    if path_name == "" then
      path_name = "/"
    end
    return path_name
  end

  local function get_files(file_dir)
    last_dir_cache = file_dir
    curr_dir_cache = {}

    local dir = uv.fs_scandir(file_dir)
    if dir == nil then
      return
    end

    while true do
      local file = uv.fs_scandir_next(dir)
      if file == nil then
        return
      end
      table.insert(curr_dir_cache, file)
    end
  end

  ---@return boolean
  local function is(dir, identifier)
    dir = dir:match(".*/(.*)")
    return dir == identifier
  end

  ---@return boolean
  local function sub(dir, identifier)
    local path_name = get_parent(dir)
    while true do
      if is(path_name, identifier) then
        return true
      end
      local current = path_name
      path_name = get_parent(path_name)
      if current == path_name then
        return false
      end
    end
  end

  ---@return boolean
  local function child(dir, identifier)
    local path_name = get_parent(dir)
    return is(path_name, identifier)
  end

  ---@return boolean
  local function has(dir, identifier)
    if last_dir_cache ~= dir then
      get_files(dir)
    end
    local pattern = glob.globtopattern(identifier)
    for _, file in ipairs(curr_dir_cache) do
      if file:match(pattern) ~= nil then
        return true
      end
    end
    return false
  end

  local function match(dir, pattern)
    local first_char = pattern:sub(1, 1)
    if first_char == "=" then
      return is(dir, pattern:sub(2))
    elseif first_char == "^" then
      return sub(dir, pattern:sub(2))
    elseif first_char == ">" then
      return child(dir, pattern:sub(2))
    else
      return has(dir, pattern)
    end
  end

  while true do
    -- log("search dir: ", search_dir)
    for pattern_type, pattern_list in pairs(config.project.root_patterns) do
      -- log("type: ", pattern_type)
      for _, pattern in ipairs(pattern_list) do
        -- log("pattern: ", pattern)
        local exclude = false
        if pattern:sub(1, 1) == "!" then
          exclude = true
          pattern = pattern:sub(2)
        end
        if match(search_dir, pattern) then
          if exclude then
            break
          else
            return search_dir, pattern_type, pattern
          end
        end
      end
    end

    local parent = get_parent(search_dir)
    if parent == search_dir or parent == nil then
      return nil
    end

    search_dir = parent
  end
end

---Determine the current project. Will use several heuristic to determine the project name
---if none succeeds it will return nil
---@return string|nil, string|nil, string|nil
function M.get_project_root()
  for _, detection_method in ipairs(config.project.detection_methods) do
    if detection_method == "lsp" then
      local root, lsp_name = M.find_lsp_root()
      if root ~= nil and not M.is_excluded(root) then
        return root, lsp_name, "lsp"
      end
    elseif detection_method == "pattern" then
      local root, pattern_type, method = M.find_pattern_root()
      if root ~= nil and not M.is_excluded(root) then
        return root, pattern_type, method
      end
    end
  end
  return nil
end

function M.get_project_name()
  local root, pattern_type, method = M.get_project_root()
  -- log(root, pattern_type, method)

  if root == nil or root == "" then
    return nil
  end

  local project_name = ""
  if root ~= nil then
    -- default value
    project_name = root:match("/*.*/(.*)$")
    -- log("default name:", project_name)
  end

  if method == "json" then
    if config.project.json_tags ~= nil and #config.project.json_tags ~= 0 then
      local content = utils.read_file(root .. "/" .. method)
      if content ~= nil then
        local json = fn.json_decode(content)
        if json ~= nil then
          for _, tag in ipairs(config.project.json_tags) do
            if json[tag] ~= nil then
              project_name = json[tag]
              -- log("json:", project_name)
            end
          end
        end
      end
    end
  end

  if method == "extension" then
    local name = root:match(".*/(.*)\\" .. method)
    if name ~= nil then
      project_name = name
    end
  end

  -- if the extension must be removed we do it unless the project name starts with a dot
  if project_name ~= "" and project_name:sub(1, 1) ~= "." and config.project.remove_extension then
    project_name = project_name:match("([^.]*)[\\.]*.*$")
  end

  -- we look for synonmyms and if found we return the main name
  -- log("project synonyms: ", config.project.project_synonyms, #config.project.project_synonyms)
  if config.project.project_synonyms ~= nil then
    for project, synonym in pairs(config.project.project_synonyms) do
      -- log("Synonym:", project, synonym)
      if synonym ~= nil then
        if type(synonym) ~= nil and type(synonym) == "string" and project_name == synonym then
          return project
        end
        if type(synonym) ~= nil and type(synonym) == "table" then
          for _, term in pairs(synonym) do
            if project_name == term then
              return project
            end
          end
        end
      end
    end
  end

  return project_name
end

---@diagnostic disable-next-line: unused-local
local on_attach_lsp = function(client, bufnr)
  M.on_buf_enter()
end

function M.attach_to_lsp()
  if M.attached_lsp then
    return
  end

  local _start_client = vim.lsp.start_client
  vim.lsp.start_client = function(lsp_config)
    if lsp_config.on_attach == nil then
      lsp_config.on_attach = on_attach_lsp
    else
      local _on_attach = lsp_config.on_attach
      lsp_config.on_attach = function(client, bufnr)
        on_attach_lsp(client, bufnr)
        _on_attach(client, bufnr)
      end
    end
    return _start_client(lsp_config)
  end

  M.attached_lsp = true
end

function M.is_file()
  local buf_type = api.nvim_get_option_value("buftype", {})

  local whitelisted_buf_type = { "", "acwrite" }
  local is_in_whitelist = false
  for _, wtype in ipairs(whitelisted_buf_type) do
    if buf_type == wtype then
      is_in_whitelist = true
      break
    end
  end
  if not is_in_whitelist then
    return false
  end

  return true
end

function M.on_buf_enter()
  if vim.v.vim_did_enter == 0 then
    return
  end

  if not M.is_file() then
    return
  end

  local current_dir = fn.expand("%:p:h", true)
  if not M.exists(current_dir) or M.is_excluded(current_dir) then
    return
  end

  local root, _, _ = M.get_project_root()
  M.set_pwd(root)
end

function M.setup()
  local autocmds = {}
  autocmds[#autocmds + 1] = 'autocmd VimEnter,BufEnter * ++nested lua require("taskforge.project").on_buf_enter()'

  if vim.tbl_contains(config.project.detection_methods, "lsp") then
    M.attach_to_lsp()
  end

  vim.cmd([[
    command! ProjectRoot lua require("taskforge.project").on_buf_enter()
  ]])

  vim.cmd([[augroup project_nvim
            au!
  ]])
  for _, value in ipairs(autocmds) do
    vim.cmd(value)
  end
  vim.cmd("augroup END")
end

return M
```

taskforge.nvim/lua//taskforge//subcommands.lua
```lua
local commands = require("taskforge.commands")
local utils = require("taskforge.utils.utils")

local subcommands = {}

function subcommands.complete(arg, cmd_line)
  local matches = {}
  local lack_taskwarrior_tui = vim.fn.executable("taskwarrior-tui") ~= 1

  local words = vim.split(cmd_line, " ", { trimempty = true })
  if not vim.endswith(cmd_line, " ") then
    -- Last word is not fully typed, don't count it
    table.remove(words, #words)
  end

  if #words == 1 then
    for subcommand in pairs(commands) do
      if
        vim.startswith(subcommand, arg) and not vim.startswith(subcommand, "auto") and subcommand ~= "setup"
        or lack_taskwarrior_tui and subcommand ~= "taskwarrior_tui"
      then
        table.insert(matches, subcommand)
      end
    end
  end

  return matches
end

function subcommands.run(subcommand)
  local subcommand_func = commands[subcommand.fargs[1]]
  if not subcommand_func then
    utils.notify("No such subcommand: " .. subcommand.fargs[1], vim.log.levels.ERROR)
    return
  end
  subcommand_func(subcommand.bang)
end

return subcommands
```

taskforge.nvim/lua//taskforge//tag-tracker.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
local M = {}

function M.setup() end

return M
```

taskforge.nvim/lua//taskforge//tasks.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
local M = {}
local config = require("taskforge.utils.config")
local cache = require("taskforge.utils.cache")
local exec = require("taskforge.utils.exec")
local utils = require("taskforge.utils.utils")
local todo = {}

M.tasks = {}
M.tasks_status = "invalid"

local function process_tasks(result)
  if result.ok then
    vim.schedule(function()
      local json_text = table.concat(result.value.stdout, "\n")
      _, M.tasks = pcall(vim.fn.json_decode, json_text)
      M.tasks_status = "valid"
    end)
  else
    M.tasks = {}
  end
end

local function get_tasks_async(filter, include_completed)
  M.tasks_status = "refreshing"
  local cmd = "task"
  local args = { filter or "", "export" }
  if not include_completed then
    args[#args + 1] = "long"
  end
  local opts = { async = true, separators = nil, remove_sep = nil }
  return exec.exec(cmd, args, opts, process_tasks)
end

local function get_tasks(limit, project, exclude)
  local prj_string = ""
  if project then
    if exclude and exclude == true then
      prj_string = "and project.not:" .. project
    else
      prj_string = "and project:" .. project
    end
  end
  local cmd = string.format("task status:pending %s export ls ", prj_string)
  local handle = io.popen(cmd)
  if handle == nil then
    return {}
  end
  local result = handle:read("*a")
  handle:close()
  if result == nil then
    return {}
  end
  local tasks = vim.fn.json_decode(result)
  utils.sort_by_column(tasks, "urgency")
  if limit > 0 then
    return utils.slice(tasks, 1, limit)
  end
  return tasks
end

function M.get_dashboard_tasks(limit, project, exclude)
  limit = limit or config.dashboard.limit
  return get_tasks(limit, project, exclude)
end

local function build_task_dict(tasks)
  local task_dict = {}
  for _, task in ipairs(tasks) do
    task_dict[task.uuid] = task
  end
  return task_dict
end

local function find_root_tasks_depends(tasks)
  -- local root_tasks = {}
  -- for _, task in ipairs(tasks) do
  -- 	if not task.depends or #task.depends == 0 then
  -- 		table.insert(root_tasks, task)
  -- 	end
  -- end
  -- return root_tasks
  local is_dependent = {}

  -- Mark all tasks that are dependencies
  for _, task in ipairs(tasks) do
    if task.depends then
      for _, dep_id in ipairs(task.depends) do
        is_dependent[dep_id] = true
      end
    end
  end

  -- Root tasks are those that are not marked as dependencies
  local root_tasks = {}
  for _, task in ipairs(tasks) do
    if not is_dependent[task.uuid] then
      table.insert(root_tasks, task)
    end
  end

  return root_tasks
end

-- Recursive function to print tasks hierarchically
local function add_todo(task, task_dict, indent)
  indent = indent or 0
  table.insert(todo, { indent = indent, task = task })
  if task.depends then
    for _, dep_id in ipairs(task.depends) do
      if task_dict[dep_id] then
        add_todo(task_dict[dep_id], task_dict, indent + 1)
      end
    end
  end
end

local function get_todo_depends(tasks)
  local task_dict = build_task_dict(tasks)
  local root_tasks = find_root_tasks_depends(tasks) or {}
  todo = {}
  for _, root_task in ipairs(root_tasks) do
    add_todo(root_task, task_dict)
  end
  return todo
end

function M.get_todo(project, group_by, limit)
  limit = limit or -1
  group_by = group_by or "depends"
  local tasks = M.get_tasks(limit, project)
  if group_by == "depends" then
    return get_todo_depends(tasks)
  else
    return {}
  end
end

function M.setup()
  -- local handle = get_tasks_async(nil, false)
  -- if handle ~= nil then
  --   print("Handle: ", handle.is_closing)
  -- end

  -- Emit signal if database file is modified
  -- M.fs_event = vim.loop.new_fs_event()
  -- M.fs_event:start(
  --   cache.data_file,
  --   {},
  --   vim.schedule_wrap(function(err, filename, event)
  --     if err then
  --       vim.notify("Cannot watch the Taskwarrior database, error: " .. err, vim.log.levels.ERROR)
  --       return
  --     else
  --       EventEmitter:emit("Taskwarrior:database_changed", filename, events)
  --     end
  --   end)
  -- )
end

return M
```

# taskforge.nvim/lua//taskforge//utils/
taskforge.nvim/lua//taskforge//utils//cache.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
local exec = require("taskforge.utils.exec")

-- Default cache structure
---@class TaskforgeCache
local Cache = {
  has_taskwarrior = nil,
  has_taskwarrior_tui = nil,
  has_taskopen = nil,
  -- database
  data_file = nil,
  data_file_exists = nil,
  -- has dashboard plugins
  has_snacks_dashboard = nil,
  has_dashboard = nil,
  -- has picker plugins
  has_snacks_picker = nil,
  has_telescope = nil,
  has_fzf_lua = nil,
  -- Main switch
  valid = nil,
  -- Container
  container = {},
}

function Cache:setup()
  -- setup environment cache
  self.has_taskwarrior = vim.fn.executable("task") == 1
  self.has_taskwarrior_tui = vim.fn.executable("taskwarrior-tui") == 1
  self.has_taskopen = vim.fn.executable("taskopen") == 1

  -- get the data file location
  local opts = { separators = { "\n", " " } }
  local cmd = "task"
  local data_folder = exec.exec(cmd, { "_get", "rc.data.location" }, opts)
  if data_folder.ok then
    local data = data_folder.value
    self.data_file = data.stdout .. "/taskchampion.sqlite3"
    self.data_file_exists = vim.fn.filereadable(self.data_file) == 1
  else
    self.data_file_exists = false
  end

  -- Which dashboard do we have available
  self.has_snacks_dashboard = package.loaded["Snacks.dashboard"] ~= nil
  self.has_dashboard = package.loaded["dashboard-nvim"] ~= nil

  -- Which picker do we have available
  self.has_snacks_picker = package.loaded["Snacks.picker"] ~= nil
  self.has_telescope = package.loaded["telescope"] ~= nil
  self.has_fzf_lua = package.loaded["fzf-lua"] ~= nil

  -- Main switch
  self.valid = self.has_taskwarrior and self.data_file_exists and vim.fn.has("nvim-0.10") == 1
end

return Cache
```

taskforge.nvim/lua//taskforge//utils//config.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--

-- Default configuration structure
---@class TaskforgeOptions
local Config = {
  -- debug hook
  debug = {
    enable = nil,
    log_file = nil,
    log_max_len = nil,
  },
  -- Project naming configuration
  project = {
    -- project prefix, will be separated by a dot with the project name
    prefix = "",
    -- default project name for situations where the tagged files do not belong to an identified project
    default_project = "project",
    -- indicate whether the postfix is made by the path of the tagged file, the filename of the tagged file or both
    postfix = "PATH|FILENAME",
    -- default separator, path components are replaced with this separator
    separator = ".",

    -- project root heuristic
    detection_methods = { "lsp", "pattern" },
    -- project root pattern (order)
    root_patterns = {
      extensions = { -- extensions file which file name are the project name
        ".csproj", -- .NET project name
        ".xcodeproj", -- Xcode project name
      },
      signature = { -- existence of a file or a folder in the root folder which is the project name
        ".git", -- git repository
        "_darcs", -- darc repository
        ".hg", -- mercurial repository
        ".bzr", -- bazaar repository
        ".svn", -- subversion repository
        "Makefile",
      },
      json = { -- json file which contains information about the project including its name
        "project.json",
        "package.json",
      },
      exclude_dirs = { -- folders which should be excluded from the search (hence the project name would fall back to its default)
      },
    },
    -- extract project name from json file
    json_tags = { "project", "name" },
    -- project info file
    project_info = ".taskforge.json",
    -- remove any extension from the project name
    remove_extension = true,
    project_synonyms = {},
  },

  -- Tag tracking configuration
  tags = {
    -- enable tag tracking
    enable = true,
    -- auto refresh the task list for the current project
    auto_refresh = true,
    -- require confirmation for ask and manual, if set to false ask will behave like auto and manual won't require a confirmation
    confirmation = true,
    -- languages for which the plugin is active
    enabled_ft = {
      "*",
      -- "c",
      -- "cpp",
      -- "go",
      -- "hjson",
      -- "java",
      -- "javascript",
      -- "lua",
      -- "markdown",
      -- "python",
      -- "rust",
      -- "typescript",
      -- "zig",
    },
    --
    debounce = 500, -- time in ms to wait before updating taskwarrior after a change
    definitions = {
      -- format of the tags
      tag_format = ".*:",
      ["TODO"] = {
        priority = "M", -- default taskwarrior priority
        tags = { "coding", "enhancement" }, -- default taskwarrior tags
        due = "+1w", -- due date relative to the creation date
        alt = {}, -- alternative tags
        create = "ask", -- ask|auto|manual  action when the tag is created
        -- ask: the plugin will ask the user if a task should be created
        -- auto: a task will be auto created
        -- manual: a notification will be displayed to remind the user to create a task
        close = "auto",
      },
      ["WARN"] = {
        priority = "H",
        tags = { "coding", "warning" },
        due = "+3d",
        alt = { "WARNING", "XXX" },
        create = "auto",
        close = "auto",
      },
      ["FIX"] = {
        priority = "H",
        tags = { "coding", "bug" },
        due = "+2d",
        alt = { "FIXME", "BUG", "FIXIT", "ISSUE" },
        create = "auto",
        close = "auto",
      },
      ["PERF"] = {
        priority = "M",
        tags = { "coding", "performance" },
        due = "+1w",
        alt = { "OPTIM", "OPTIMIZE", "PERFORMANCE" },
        create = "auto",
        close = "ask",
      },
      ["TEST"] = {
        priority = "L",
        tags = { "coding", "testing" },
        due = nil,
        alt = { "TESTING", "PASSED", "FAILED" },
        create = "auto",
        close = "manual",
      },
    },
  },

  -- Dashboard integration
  dashboard = {
    --- function to reload dashboard config
    get_dashboard_config = nil,
    -- Options for Snacks.nvim dashboard
    snacks_options = {
      key = "t",
      action = "taskwarrior-tui", -- "taskwarrior-tui"|"project"|"tasks"
      icon = "",
      title = "Tasks",
      height = nil,
      pane = nil,
      enable = false,
      padding = 1,
      indent = 3,
    },
    -- Options for Dashboard.nvim
    dashboard_options = {},
    format = {
      -- maximum number of tasks
      limit = 5,
      -- maximum number of non-project tasks
      non_project_limit = 5,
      -- Defines the section separator
      sec_sep = ".",
      -- Enable or disable section shortening
      shorten_sections = true,
      -- Maximum width
      max_width = 55,
      -- Columns to be shown
      columns = {
        "id",
        "project",
        "description",
        "due",
        "urgency",
      },
      -- Abbreviations to shorten project names
      project_abbreviations = {},
    },
  },

  -- Task interface configuration
  interface = {
    keymaps = {
      open = "o", -- if tracked,
      close_task = "d",
      modify_task = "m",
      annotate_task = "A",
      add_task = "a",
      filter = "/",
      sort = "s",
      quit = "q",
    },
    view = {
      default = "list", -- or "tree" for dependency view
      position = "right",
      width = 40,
    },
    integrations = {
      telescope = true,
      fzf = true,
    },
  },

  -- Highlighting
  highlights = {
    urgent = {
      threshold = 8.0,
      group = nil, -- Will use @keyword if nil
    },
    normal = {
      group = nil, -- Will use Comment if nil
    },
  },
}

function Config:setup(options)
  local new_config = vim.tbl_deep_extend("force", self, options)
  for key, value in pairs(new_config) do
    self[key] = value
  end
end

return Config
```

taskforge.nvim/lua//taskforge//utils//debug.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License

-- Credit for the inspiration of this module goes to folke's Snacks.debug module

---@class debug
---@overload fun(...)
local M = setmetatable({}, {
  __call = function(t, ...)
    return t.inspect(...)
  end,
})

M.debug_config = {}

local debug_query = "Sn"
local cache_dir = {}

M.meta = {
  desc = "Pretty inspect & backtraces for debugging",
}

local uv = vim.uv or vim.loop

vim.schedule(function()
  Snacks.util.set_hl({
    Indent = "LineNr",
    Print = "NonText",
  }, { prefix = "SnacksDebug", default = true })
end)

-- Show a notification with a pretty printed dump of the object(s)
-- with lua treesitter highlighting and the location of the caller
function M.inspect(...)
  local len = select("#", ...) ---@type number
  local obj = { ... } ---@type unknown[]
  local caller = debug.getinfo(1, "S")
  for level = 2, 10 do
    local info = debug.getinfo(level, "S")
    if
      info
      and info.source ~= caller.source
      and info.what ~= "C"
      and info.source ~= "lua"
      and info.source ~= "@" .. (os.getenv("MYVIMRC") or "")
    then
      caller = info
      break
    end
  end
  vim.schedule(function()
    local title = "Debug: " .. vim.fn.fnamemodify(caller.source:sub(2), ":~:.") .. ":" .. caller.linedefined
    Snacks.notify.warn(vim.inspect(len == 1 and obj[1] or len > 0 and obj or nil), { title = title, ft = "lua" })
  end)
end

-- Show a notification with a pretty backtrace
---@param msg? string|string[]
---@param opts? snacks.notify.Opts
function M.backtrace(msg, opts)
  opts = vim.tbl_deep_extend("force", {
    level = vim.log.levels.WARN,
    title = "Backtrace",
  }, opts or {})
  ---@type string[]
  local trace = type(msg) == "table" and msg or type(msg) == "string" and { msg } or {}
  for level = 2, 20 do
    local info = debug.getinfo(level, "Sln")
    if info and info.what ~= "C" and info.source ~= "lua" and not info.source:find("snacks[/\\]debug") then
      local line = "- `" .. vim.fn.fnamemodify(info.source:sub(2), ":p:~:.") .. "`:" .. info.currentline
      if info.name then
        line = line .. " _in_ **" .. info.name .. "**"
      end
      table.insert(trace, line)
    end
  end
  local result = #trace > 0 and (table.concat(trace, "\n")) or ""
  Snacks.notify(result, opts)
end

-- Very simple function to profile a lua function.
-- * **flush**: set to `true` to use `jit.flush` in every iteration.
-- * **count**: defaults to 100
-- * **show**: default to true
---@param fn fun()
---@param opts? {count?: number, flush?: boolean, title?: string}
function M.profile(fn, opts)
  opts = vim.tbl_extend("force", { count = 100, flush = true, show = true }, opts or {})
  local start = uv.hrtime()
  for _ = 1, opts.count, 1 do
    if opts.flush then
      jit.flush(fn, true)
    end
    fn()
  end
  Snacks.notify(((uv.hrtime() - start) / 1e6 / opts.count) .. "ms", { title = opts.title or "Profile" })
end

---@param level integer
---@param debug_info table
---@return string|nil function_name, string|nil function_source
local function caller(level, debug_info)
  local function get_src(path_name)
    local source

    -- use cached value if available
    if cache_dir[path_name] ~= nil then
      return cache_dir[path_name]
    end

    -- when debugging a plugin, we'll have a structure of the kind /lua/<plugin>/file... so we look for this pattern first
    source = path_name:match(".*/lua/[^/]+/(.*).lua$"):gsub("/", ".")
    if source == nil then -- we are not in the normal pattern so we'll just return the parent folder and the filename
      source = path_name:match(".*/([^/]+/.*).lua$"):gsub("/", ".")
    end

    -- cache the new value before returning it
    cache_dir[path_name] = source

    return source
  end

  level = level + 1 -- this is to account for the fact by calling this function we are one level deeper
  if debug_info.name == nil or debug_info.name == "" then
    local name, source = caller(level, debug.getinfo(level, debug_query))
    return name .. ".fn", source -- we add the indication that there is an anonymous function
  else
    return debug_info.name, get_src(debug_info.source)
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
function M.log(...)
  local level = 3 -- level 3 because we expect the caller to be a global function
  local caller_fn, caller_src = caller(level, debug.getinfo(level, debug_query))
  local file = M.debug_config.log_file or "./debug.log"
  local fd = io.open(file, "a+")
  if not fd then
    error(("Could no t open file %s for writing"):format(file))
  end
  local c = select("#", ...)
  local parts = {} ---@type string[]
  for i = 1, c do
    local v = select(i, ...)
    parts[i] = type(v) == "string" and v or vim.inspect(v)
  end
  local msg = " | " .. caller_src .. "." .. caller_fn
  local arg = table.concat(parts, " ")
  if #arg ~= 0 then
    msg = msg .. " | " .. arg
  end
  msg = #msg < (M.debug_config.log_max_len or 120) and msg:gsub("%s+", " ") or msg
  fd:write(os.date("%Y-%m-%d %H:%M:%S ") .. msg)
  fd:write("\n")
  fd:close()
end

---@alias debug.Trace {name: string, time: number, [number]:snacks.debug.Trace}
---@alias debug.Stat {name:string, time:number, count?:number, depth?:number}

---@type debug.Trace[]
M._traces = { { name = "__TOP__", time = 0 } }

---@param name string?
function M.trace(name)
  if name then
    local entry = { name = name, time = uv.hrtime() } ---@type snacks.debug.Trace
    table.insert(M._traces[#M._traces], entry)
    table.insert(M._traces, entry)
    return entry
  else
    local entry = assert(table.remove(M._traces), "trace not ended?") ---@type snacks.debug.Trace
    entry.time = uv.hrtime() - entry.time
    return entry
  end
end

---@param modname string
---@param mod? table
---@param suffix? string
function M.tracemod(modname, mod, suffix)
  mod = mod or require(modname)
  suffix = suffix or "."
  for k, v in pairs(mod) do
    if type(v) == "function" and k ~= "trace" then
      mod[k] = function(...)
        M.trace(modname .. suffix .. k)
        local ok, ret = pcall(v, ...)
        M.trace()
        return ok == false and error(ret) or ret
      end
    end
  end
end

---@param opts? {min?: number, show?:boolean}
---@return {summary:table<string, snacks.debug.Stat>, trace:snacks.debug.Stat[], traces:snacks.debug.Trace[]}
function M.stats(opts)
  opts = opts or {}
  local stack, lines, trace = {}, {}, {} ---@type string[], string[], snacks.debug.Stat[]
  local summary = {} ---@type table<string, snacks.debug.Stat>
  ---@param stat snacks.debug.Trace
  local function collect(stat)
    if #stack > 0 then
      local recursive = vim.list_contains(stack, stat.name)
      summary[stat.name] = summary[stat.name] or { time = 0, count = 0, name = stat.name }
      summary[stat.name].time = summary[stat.name].time + (recursive and 0 or stat.time)
      summary[stat.name].count = summary[stat.name].count + 1
      table.insert(trace, { name = stat.name, time = stat.time or 0, depth = #stack - 1 })
    end
    table.insert(stack, stat.name)
    for _, entry in ipairs(stat) do
      collect(entry)
    end
    table.remove(stack)
  end
  collect(M._traces[1])

  ---@param entries snacks.debug.Stat[]
  local function add(entries)
    for _, stat in ipairs(entries) do
      local ms = math.floor(stat.time / 1e4) / 1e2
      if ms >= (opts.min or 0) then
        local line = ("%s- `%s`: **%.2f**ms"):format(("  "):rep(stat.depth or 0), stat.name, ms)
        table.insert(lines, line .. (stat.count and (" ([%d])"):format(stat.count) or ""))
      end
    end
  end

  if opts.show ~= false then
    lines[#lines + 1] = "# Summary"
    summary = vim.tbl_values(summary)
    table.sort(summary, function(a, b)
      return a.time > b.time
    end)
    add(summary)
    lines[#lines + 1] = "\n# Trace"
    add(trace)
    Snacks.notify.warn(lines, { title = "Traces" })
  end
  return { summary = summary, trace = trace, tree = M._traces }
end

function M.size(bytes)
  local sizes = { "B", "KB", "MB", "GB", "TB" }
  local s = 1
  while bytes > 1024 and s < #sizes do
    bytes = bytes / 1024
    s = s + 1
  end
  return ("%.2f%s"):format(bytes, sizes[s])
end

---@param show? boolean
function M.metrics(show)
  collectgarbage("collect")
  local lines = {} ---@type string[]
  local function add(name, value)
    lines[#lines + 1] = ("- **%s**: %s"):format(name, value)
  end

  add("lua", M.size(collectgarbage("count") * 1024))

  for _, stat in ipairs({ "get_total_memory", "get_free_memory", "get_available_memory", "resident_set_memory" }) do
    add(stat:gsub("get_", ""):gsub("_", " "), M.size(uv[stat]()))
  end
  lines[#lines + 1] = ("```lua\n%s\n```"):format(vim.inspect(uv.getrusage()))
  if show == nil or show then
    Snacks.notify.warn(lines, { title = "Metrics" })
  else
    return "Metrics: " .. lines
  end
end

function M.setup(debug_config)
  if debug_config == nil then
    M.debug_config["debug"] = false
  else
    M.debug_config = debug_config
    if M.debug_config.debug == nil then
      M.debug_config.debug = false
    end
  end
  if M.debug_config.debug then
    vim.print = M.inspect
  end
  return M.debug_config.debug
end

return M
```

taskforge.nvim/lua//taskforge//utils//events.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
-- event.lua
-- Centralized event manager for custom events and system events.
-- It supports:
--   - Registering custom events and listeners (with pause/resume/off)
--   - Registering a system event handle (e.g., from vim.loop.fs_event) by event name
--   - Unregistering an entire event, which cleans up both the listeners and any system event handle.

local M = {}

-- Internal table to hold custom event listeners.
-- Structure:
--   _events = {
--     ["myplugin:event1"] = { { callback = <function>, paused = false }, ... },
--     ...
--   }
M._events = {}

-- Internal table to hold system event handles.
-- Structure:
--   _system_events = {
--     ["myplugin:event1"] = <uv handle>,
--     ...
--   }
M._system_events = {}

--------------------------------------------------------------------------------
-- Custom Event Registration and Existence Check
--------------------------------------------------------------------------------

--- Register a new custom event.
--- Only registered events may have listeners attached.
--- @param event string: The event name (use a namespace, e.g., "myplugin:event_name").
function M.register(event)
  if M._events[event] then
    vim.notify("Event '" .. event .. "' is already registered.", vim.log.levels.WARN)
    return
  end
  M._events[event] = {}
end

--- Check if a custom event is registered.
--- @param event string: The event name.
--- @return boolean: True if the event exists.
function M.exists(event)
  return M._events[event] ~= nil
end

--------------------------------------------------------------------------------
-- Listener Management for Custom Events
--------------------------------------------------------------------------------

--- Register a listener for a given custom event.
--- The event must be registered first using M.register(event).
---
--- @param event string: The event name.
--- @param callback function: The function to call when the event is emitted.
--- @return table: A handle containing the event name and a reference to the listener.
function M.on(event, callback)
  if not M.exists(event) then
    error(
      "Attempted to register a listener for unregistered event '"
        .. event
        .. "'. Check for typos or register the event first."
    )
  end

  local listener = { callback = callback, paused = false }
  table.insert(M._events[event], listener)
  -- Return a handle so the listener can later be paused, resumed, or removed.
  return { event = event, listener = listener }
end

--- Emit a custom event, calling all active (non-paused) listeners.
--- Additional arguments are passed to the listener callbacks.
---
--- @param event string: The event name.
--- @param ...: Arguments to pass to the callbacks.
function M.emit(event, ...)
  if not M.exists(event) then
    error("Attempted to emit unregistered event '" .. event .. "'.")
  end

  for _, listener in ipairs(M._events[event]) do
    if not listener.paused then
      listener.callback(...)
    end
  end
end

--- Remove (de-register) a listener using its handle.
---
--- @param handle table: The handle returned by M.on().
--- @return boolean: True if removal succeeded.
function M.off(handle)
  local event = handle.event
  if not M.exists(event) then
    error("Attempted to remove a listener from unregistered event '" .. event .. "'.")
  end

  for i, listener in ipairs(M._events[event]) do
    if listener == handle.listener then
      table.remove(M._events[event], i)
      return true
    end
  end
  return false
end

--- Pause a listener so it no longer reacts to emitted events.
--- @param handle table: The handle returned by M.on().
function M.pause(handle)
  if handle and handle.listener then
    handle.listener.paused = true
  end
end

--- Resume a previously paused listener.
--- @param handle table: The handle returned by M.on().
function M.resume(handle)
  if handle and handle.listener then
    handle.listener.paused = false
  end
end

--------------------------------------------------------------------------------
-- System Event (uv handle) Management
--------------------------------------------------------------------------------

--- Register a system event handle (for example, one returned by uv.new_fs_event)
--- and associate it with a custom event name. This lets you later retrieve or clean
--- up the system handle.
---
--- If the custom event is not already registered, it will be registered.
---
--- @param event string: The event name.
--- @param uv_handle userdata: The uv handle (e.g., from vim.loop.new_fs_event()).
function M.register_system_event(event, uv_handle)
  if not M.exists(event) then
    -- Optionally, auto-register the event if it isn't already registered.
    M.register(event)
  end
  M._system_events[event] = uv_handle
end

--- Retrieve a registered system event handle by event name.
--- @param event string: The event name.
--- @return userdata: The uv handle, or nil if not registered.
function M.get_system_event(event)
  return M._system_events[event]
end

--- Unregister a system event.
--- This stops and closes the uv handle, then removes it from the table.
--- @param event string: The event name.
function M.unregister_system_event(event)
  local handle = M._system_events[event]
  if handle then
    -- Stop and close the uv handle if it supports these methods.
    if handle.stop then
      handle:stop()
    end
    if handle.close then
      handle:close()
    end
    M._system_events[event] = nil
  end
end

--------------------------------------------------------------------------------
-- Unregistering an Entire Event (Custom and System)
--------------------------------------------------------------------------------

--- Unregister an entire event.
--- This function removes all custom listeners for the event and, if a system event
--- handle is registered with this event, it unregisters that as well.
---
--- @param event string: The event name.
function M.unregister_event(event)
  if not M.exists(event) then
    vim.notify("Cannot unregister non-existing event: " .. event, vim.log.levels.WARN)
    return
  end

  -- Remove all custom listeners by setting the table to nil.
  M._events[event] = nil

  -- Unregister the associated system event, if any.
  if M._system_events[event] then
    M.unregister_system_event(event)
  end
end

--------------------------------------------------------------------------------
-- (Optional) Debug Utility: List Registered Custom Events and Their Listener Count
--------------------------------------------------------------------------------

--- Return a table of registered custom events and the number of listeners for each.
function M.list_events()
  local events = {}
  for event, listeners in pairs(M._events) do
    events[event] = #listeners
  end
  return events
end

--------------------------------------------------------------------------------
-- Module Return
--------------------------------------------------------------------------------

return M
```

taskforge.nvim/lua//taskforge//utils//exec.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
--[[
Taskforge Execution Module
=======================
Purpose:
  Facilitate the execution of command asynchronously or synchronously.

Module Structure:
  - Uses Neovim API (vim.api) for buffer operations
  - Uses vim.fn for Vim function access
  - Requires Taskforge.utils.result for Result type handling
  - Exports functions through module table M

Major Components:
  1. Command Execution
     - Async/sync command execution with streaming support
     - Output processing with separator handling
     - Error handling with Result type

Dependencies:
  - Neovim 0.10+ for vim.system()
  - Taskforge.utils.result for Result type
--]]

local Result = require("taskforge.utils.result")

local M = {}

---@class Taskforge.utils.Streams
---@field stdout function Iterator for stdout lines
---@field stderr function Iterator for stderr lines

---@class Taskforge.utils.ExecResult
---@field code number Exit code of the process
---@field signal number|nil Signal that terminated the process, if any
---@field streams Taskforge.utils.Streams|nil Stream iterators when in streaming mode
---@field stdout string[]|nil Complete stdout output when not streaming
---@field stderr string[]|nil Complete stderr output when not streaming
---@field timeout boolean True if process was terminated due to timeout

---@class Taskforge.utils.ExecError
---@field code number Exit code of the process
---@field stderr string Error output from the process
---@field message string Human readable error message

---@class Taskforge.utils.ExecOptions
---@field async boolean|nil Execute asynchronously (default: false)
---@field timeout number|nil Timeout in milliseconds (only for async)
---@field env table|nil Environment variables to set
---@field clear_env boolean|nil Clear environment before setting env variables
---@field cwd string|nil Working directory for command execution
---@field stream boolean|nil Stream output instead of collecting (only for async, default: false)
---@field separators string[]|nil Separators for splitting stdout (default: {"\n"})
---@field remove_sep boolean|nil Remove separators from output (default: true)
---@field text boolean|nil Handle stdin and stderr as text

---Split text using multiple separators while preserving empty elements
---Note: Separators are treated as literal strings, not regex patterns
---Order of separators may affect the output when they overlap
---@param text string Text to split
---@param separators string[] Array of separator strings
---@param remove_sep boolean Whether to remove separators from output
---@return string|string[] Single string if empty/single result, array otherwise
local function split_text(text, separators, remove_sep)
  -- Handle the trivial cases
  if text == "" then
    return ""
  end

  if separators == nil or #separators == 0 then
    return text
  end

  -- First split by each separator in sequence
  local parts = { text }
  for _, sep in ipairs(separators) do
    local new_parts = {}
    for _, part in ipairs(parts) do
      -- Split and process each part
      local start = 1
      local pattern = vim.pesc(sep)
      while start <= #part do
        local sep_start, sep_end = part:find(pattern, start, true)
        if not sep_start then
          -- Add remaining part (including empty strings)
          table.insert(new_parts, part:sub(start))
          break
        end

        -- Add part with or without separator
        local piece = remove_sep and part:sub(start, sep_start - 1) or part:sub(start, sep_end)
        table.insert(new_parts, piece)

        -- Move past this separator
        start = sep_end + 1
      end
    end
    parts = new_parts
  end

  -- Return appropriate type based on result count
  if #parts == 0 then
    return ""
  elseif #parts == 1 then
    return parts[1]
  end

  return parts
end

---Creates a line iterator that handles unicode characters correctly
---@param buffer table Table containing output chunks
---@param separators string[] Separators for splitting
---@param remove_sep boolean Whether to remove separators
---@return function Iterator function
local function create_line_iterator(buffer, separators, remove_sep)
  -- Process buffer content with unicode awareness
  local lines = split_text(table.concat(buffer), separators, remove_sep)

  -- Handle single string result
  if type(lines) == "string" then
    lines = { lines }
  end

  local idx = 0
  return function()
    idx = idx + 1
    return idx <= #lines and lines[idx] or nil
  end
end

---Creates an error result for command execution
---@param code number Error code
---@param stderr string Error output
---@param message string Error message
---@return Taskforge.utils.Result<Taskforge.utils.ExecResult, Taskforge.utils.ExecError>
local function make_error(code, stderr, message)
  return Result.err({
    code = code,
    stderr = stderr,
    message = message,
  })
end

---Creates a standardized result object from process output
---@param output table Output from vim.system or similar
---@param stdout_buffer table|nil Buffer containing stdout chunks
---@param stderr_buffer table|nil Buffer containing stderr chunks
---@param stream boolean|nil Whether to use streaming
---@param separators string[] Separators for splitting stdout
---@param remove_sep boolean Whether to remove separators
---@return Taskforge.utils.ExecResult
local function create_result(output, stdout_buffer, stderr_buffer, stream, separators, remove_sep)
  local result = {
    code = output.code or -1,
    signal = output.signal,
    timeout = false,
  }

  if stream then
    result.streams = {
      stdout = create_line_iterator(stdout_buffer or {}, separators, remove_sep),
      stderr = create_line_iterator(stderr_buffer or {}, { "\n" }, true),
    }
    result.stdout = nil
    result.stderr = nil
  else
    result.streams = nil
    -- Process outputs with unicode awareness
    local stdout_text = table.concat(stdout_buffer or {})
    local stderr_text = table.concat(stderr_buffer or {})

    result.stdout = split_text(stdout_text, separators, remove_sep)
    result.stderr = split_text(stderr_text, { "\n" }, true)
  end

  return result
end

---Execute a command with given options
---@param cmd string Command to execute
---@param args string[]|nil Arguments for the command
---@param opts Taskforge.utils.ExecOptions|nil Options for execution
---@param callback function|nil Callback for async execution (required if async=true)
---@return Taskforge.utils.Result<Taskforge.utils.ExecResult|nil, Taskforge.utils.ExecError>
function M.exec(cmd, args, opts, callback)
  -- Default options
  local opts_default = {
    async = false,
    separators = { "\n" },
    remove_sep = true,
  }

  opts = vim.tbl_deep_extend("force", opts_default, opts or {})
  args = args or {}

  -- Validate options
  if opts.async and callback == nil then
    return make_error(-1, "", "Callback is required for async execution")
  end

  if opts.stream and not opts.async then
    return make_error(-1, "", "Streaming is only available in async mode")
  end

  -- Prepare command arguments
  local command = { cmd, unpack(args) }

  -- Prepare system options
  local system_opts = {}
  local system_opts_handle = { "cwd", "env", "clear_env", "timeout", "text" }
  for _, handle in ipairs(system_opts_handle) do
    if opts[handle] ~= nil then
      system_opts[handle] = opts[handle]
    end
  end

  if opts.async then
    -- Setup output handling for async mode
    local stdout_buffer = {}
    local stderr_buffer = {}

    -- Always capture output in async mode
    system_opts.stdout = function(_, data)
      if data then
        table.insert(stdout_buffer, data)
      end
    end

    system_opts.stderr = function(_, data)
      if data then
        table.insert(stderr_buffer, data)
      end
    end

    -- Start async process
    local handle = vim.system(command, system_opts, function(obj)
      -- Handle different completion states
      if obj.code ~= 0 then
        callback(
          make_error(
            obj.code,
            table.concat(split_text(table.concat(stderr_buffer), { "\n" }, true), "\n"),
            "Process failed with code " .. obj.code
          )
        )
      else
        -- Process the buffers according to separators
        local result = create_result({
          code = obj.code,
          signal = obj.signal,
        }, stdout_buffer, stderr_buffer, opts.stream, opts.separators, opts.remove_sep)
        callback(Result.ok(result))
      end
    end)

    if not handle then
      return make_error(-1, "", "Failed to start process")
    end
    return Result.ok(nil) -- Successful async start
  else
    -- Synchronous execution
    local result = vim.system(command, system_opts):wait()

    -- Handle different completion states
    if result.code ~= 0 then
      -- Process stderr according to newline separator
      local stderr = split_text(result.stderr or "", { "\n" }, true)
      return make_error(
        result.code,
        type(stderr) == "table" and table.concat(stderr, "\n") or stderr,
        "Process failed with code " .. result.code
      )
    end

    -- Process outputs directly
    local stdout = result.stdout or ""
    local stderr = result.stderr or ""

    return Result.ok(create_result({
      code = result.code,
      signal = result.signal,
    }, { stdout }, { stderr }, false, opts.separators, opts.remove_sep))
  end
end

return M
```

taskforge.nvim/lua//taskforge//utils//globtopattern.lua
```lua
-- Credits for this module goes to: David Manura
-- https://github.com/davidm/lua-glob-pattern

local M = { _TYPE = "module", _NAME = "globtopattern", _VERSION = "0.2.1.20120406" }

function M.globtopattern(g)
  -- Some useful references:
  -- - apr_fnmatch in Apache APR.  For example,
  --   http://apr.apache.org/docs/apr/1.3/group__apr__fnmatch.html
  --   which cites POSIX 1003.2-1992, section B.6.

  local p = "^" -- pattern being built
  local i = 0 -- index in g
  local c -- char at index i in g.

  -- unescape glob char
  local function unescape()
    if c == "\\" then
      i = i + 1
      c = g:sub(i, i)
      if c == "" then
        p = "[^]"
        return false
      end
    end
    return true
  end

  -- escape pattern char
  local function escape(c)
    return c:match("^%w$") and c or "%" .. c
  end

  -- Convert tokens at end of charset.
  local function charset_end()
    while 1 do
      if c == "" then
        p = "[^]"
        return false
      elseif c == "]" then
        p = p .. "]"
        break
      else
        if not unescape() then
          break
        end
        local c1 = c
        i = i + 1
        c = g:sub(i, i)
        if c == "" then
          p = "[^]"
          return false
        elseif c == "-" then
          i = i + 1
          c = g:sub(i, i)
          if c == "" then
            p = "[^]"
            return false
          elseif c == "]" then
            p = p .. escape(c1) .. "%-]"
            break
          else
            if not unescape() then
              break
            end
            p = p .. escape(c1) .. "-" .. escape(c)
          end
        elseif c == "]" then
          p = p .. escape(c1) .. "]"
          break
        else
          p = p .. escape(c1)
          i = i - 1 -- put back
        end
      end
      i = i + 1
      c = g:sub(i, i)
    end
    return true
  end

  -- Convert tokens in charset.
  local function charset()
    i = i + 1
    c = g:sub(i, i)
    if c == "" or c == "]" then
      p = "[^]"
      return false
    elseif c == "^" or c == "!" then
      i = i + 1
      c = g:sub(i, i)
      if c == "]" then
        -- ignored
      else
        p = p .. "[^"
        if not charset_end() then
          return false
        end
      end
    else
      p = p .. "["
      if not charset_end() then
        return false
      end
    end
    return true
  end

  -- Convert tokens.
  while 1 do
    i = i + 1
    c = g:sub(i, i)
    if c == "" then
      p = p .. "$"
      break
    elseif c == "?" then
      p = p .. "."
    elseif c == "*" then
      p = p .. ".*"
    elseif c == "[" then
      if not charset() then
        break
      end
    elseif c == "\\" then
      i = i + 1
      c = g:sub(i, i)
      if c == "" then
        p = p .. "\\$"
        break
      end
      p = p .. escape(c)
    else
      p = p .. escape(c)
    end
  end
  return p
end

return M
```

taskforge.nvim/lua//taskforge//utils//path.lua
```lua
local config = require("taskforge.utils.config")
local uv = vim.loop
local M = {}

M.datapath = vim.fn.stdpath("data") -- directory
M.projectpath = M.datapath .. "/project_nvim" -- directory
M.historyfile = M.projectpath .. "/project_history" -- file

function M.init()
  M.datapath = require("project_nvim.config").options.datapath
  M.projectpath = M.datapath .. "/project_nvim" -- directory
  M.historyfile = M.projectpath .. "/project_history" -- file
end

function M.create_scaffolding(callback)
  if callback ~= nil then -- async
    uv.fs_mkdir(M.projectpath, 448, callback)
  else -- sync
    uv.fs_mkdir(M.projectpath, 448)
  end
end

return M
```

taskforge.nvim/lua//taskforge//utils//result.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
--[[
Result Type Module
=================
Purpose:
  Provides a Result type for error handling, inspired by Rust's Result type.
  Wraps either a success value or an error value with type safety.

Requirements and Assumptions:
---------------------------
Module Structure:
  - Standalone module
  - Uses Lua metatables for computed properties
  - Returns single table with factory functions

Type System:
  - Uses LuaLS annotations for type checking
  - Supports generic type parameters for value and error types
  - Maintains type safety across transformations

Properties:
  - ok: boolean flag for success state
  - err: computed boolean, always opposite of ok
  - value: holds success value (nil if error)
  - error: holds error value (nil if success)

Performance Considerations:
  - Metatable lookup adds minimal overhead
  - Single metatable shared across all Result instances
  - Memory overhead is one table per Result instance plus one shared metatable
--]]

---@class Taskforge.utils.Result<T, E>
---@field ok boolean Whether the operation was successful
---@field err boolean Whether the operation was unsuccessful (computed from ok)
---@field value T|nil The result if ok is true
---@field error E|nil The error information if ok is false

local M = {}

-- Create shared metatable with err property
local result_mt = {
  __index = function(t)
    -- Only compute err property
    if rawget(t, "ok") ~= nil then
      return not t.ok
    end
  end,
}

---Creates a success Result
---@generic T
---@param value T
---@return Taskforge.utils.Result<T, any>
function M.ok(value)
  return setmetatable({
    ok = true,
    value = value,
    error = nil,
  }, result_mt)
end

---Creates an error Result
---@generic E
---@param error E
---@return Taskforge.utils.Result<any, E>
function M.err(error)
  return setmetatable({
    ok = false,
    value = nil,
    error = error,
  }, result_mt)
end

return M
```

taskforge.nvim/lua//taskforge//utils//utils.lua
```lua
-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
--[[
Taskforge Utility Module
=======================
Purpose:
  Provides a collection of utility functions for the Taskforge plugin, including
  text manipulation, dashboard management, and data processing.

Module Structure:
  - Uses Neovim API (vim.api) for buffer operations
  - Uses vim.fn for Vim function access
  - Requires Taskforge.utils.result for Result type handling
  - Exports functions through module table M

Major Components:
  1. Text Processing
     - UTF-8 aware text manipulation
     - Text alignment (left, right, center)
     - Text clipping with ellipsis
     - Pattern escaping and matching

  2. Dashboard Management
     - Dashboard buffer detection
     - Dashboard refresh handling
     - Multiple dashboard type support

  3. Data Structure Operations
     - Array merging and slicing
     - Table searching and sorting
     - Project name processing

  4. Date/Time Handling
     - ISO datetime parsing
     - OS date formatting
     - Timestamp conversion

Dependencies:
  - Neovim 0.10+ for vim.system()
  - Taskforge.utils.result for Result type
  - Optional dashboard plugins (Snacks, dashboard)
--]]

local Result = require("taskforge.utils.result")

local M = {}

---Reads the entire contents of a file
---@param path string Path to the file
---@return string|nil content File contents or nil if file cannot be opened
function M.read_file(path)
  local file = io.open(path, "r")
  if not file then
    return Result.err("Could not open th file.")
  end
  local content = file:read("*a")
  file:close()
  return Result.ok(content)
end

---Checks if the current buffer is a dashboard
---@return boolean true if current buffer is a dashboard
function M.is_dashboard_open()
  local bufname = vim.api.nvim_buf_get_name(0)
  local buftype = vim.bo.filetype
  return string.match(bufname, "dashboard") or buftype == "dashboard" or buftype == "snacks_dashboard"
end

---Refreshes the current dashboard if open
---Supports both Snacks and standard dashboard plugins
function M.refresh_dashboard()
  if M.is_dashboard_open() then
    local Snacks = require("Snacks")
    if Snacks and Snacks.dashboard and type(Snacks.dashboard.update) == "function" then
      Snacks.dashboard.update()
    elseif M.get_dashboard_config and type(M.get_dashboard_config) == "function" then
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_delete(bufnr, { force = true })
      local dashboard = require("dashboard")
      dashboard.setup(M.get_dashboard_config())
      dashboard:instance()
    end
  end
end

---Clips text to specified width, adding ellipsis if needed
---@param text string Text to clip
---@param width number Maximum width allowed
---@return string Clipped text, potentially with ellipsis
function M.clip_text(text, width)
  local r_len = M.utf8len(text)
  if r_len > width then
    text = text:sub(1, (width - r_len) - 4) .. "..."
  end
  return text
end

---Merges two arrays into a new array
---@param a table First array
---@param b table Second array
---@return table result Combined array with elements from both inputs
function M.merge_arrays(a, b)
  local result = {}
  table.move(a, 1, #a, 1, result)
  table.move(b, 1, #b, #a + 1, result)
  return result
end

---Escapes special characters in a pattern
---@param text string Text to escape
---@return string Escaped pattern
local function escape_pattern(text)
  return text:gsub("([^%w])", "%%%1")
end

---Processes project name according to configuration rules
---@param project_name string Original project name
---@param config table|nil Configuration with optional abbreviations and section handling
---@return string Modified project name
function M.replace_project_name(project_name, config)
  if config and config.project_abbreviations then
    for pattern, replacement in pairs(config.project_abbreviations) do
      project_name = project_name:gsub(pattern, replacement)
    end
  end

  if config and config.shorten_sections then
    local sep = config.sec_sep
    local escaped_sep = escape_pattern(sep)
    local pattern = "[^" .. escaped_sep .. "]+"
    local parts = {}
    for part in project_name:gmatch(pattern) do
      table.insert(parts, part)
    end
    for i = 1, #parts - 1 do
      parts[i] = parts[i]:sub(1, 1)
    end
    project_name = table.concat(parts, sep)
  end
  return project_name
end

---Counts UTF-8 characters in a string
---@param str string Input string
---@return number Length in UTF-8 characters
function M.utf8len(str)
  local len = 0
  for _ in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
    len = len + 1
  end
  return len
end

---Extracts a portion of a table
---@param tbl table Source table
---@param start_index number Starting index (inclusive)
---@param end_index number Ending index (inclusive)
---@return table Sliced portion of the table
function M.slice(tbl, start_index, end_index)
  local result = {}
  for i = start_index, end_index do
    table.insert(result, tbl[i])
  end
  return result
end

---Removes leading and trailing whitespace
---@param s string String to trim
---@return string Trimmed string
local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

---Checks if a trimmed line exists in a table of lines
---@param lines_table table Table of lines to search
---@param target_line string Line to find
---@return boolean true if line found
function M.in_table(lines_table, target_line)
  target_line = trim(target_line)
  for _, line in ipairs(lines_table) do
    if line == target_line then
      return true
    end
  end
  return false
end

---Parses ISO 8601 datetime string to timestamp
---@param datetime_str string DateTime string in format "YYYYMMDDTHHMMSSZ"
---@return number|nil timestamp Unix timestamp or nil if invalid
---@return string|nil error Error message if parsing fails
function M.parse_datetime(datetime_str)
  local year, month, day, hour, min, sec = datetime_str:match("(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z")
  if not year then
    return nil, "Invalid date-time format"
  end

  local datetime_table = {
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  }

  return os.time(datetime_table)
end

---Aligns text to the right within specified width
---@param text string Text to align
---@param max_length number Maximum width
---@return string Right-aligned text
function M.align_right(text, max_length)
  local text_length = M.utf8len(text)
  if text_length < max_length then
    return string.rep(" ", max_length - text_length) .. text
  else
    return text
  end
end

---Aligns text to the left within specified width
---@param text string Text to align
---@param max_length number Maximum width
---@return string Left-aligned text
function M.align_left(text, max_length)
  local text_length = M.utf8len(text)
  if text_length < max_length then
    return text .. string.rep(" ", max_length - text_length)
  else
    return text
  end
end

---Centers text within specified width
---@param text string Text to center
---@param width number Total width
---@return string Centered text
function M.align_center(text, width)
  local text_length = M.utf8len(text)
  if text_length >= width then
    return text
  end
  local padding = (width - text_length) / 2
  local left_padding = math.floor(padding)
  local right_padding = math.ceil(padding)
  return string.rep(" ", left_padding) .. text .. string.rep(" ", right_padding)
end

---Formats ISO datetime string using os.date
---@param datetime_str string DateTime string in ISO format
---@param format_str string|nil Format string (default: "%Y-%m-%d %H:%M:%S")
---@return string Formatted date string
function M.get_os_date(datetime_str, format_str)
  format_str = format_str or "%Y-%m-%d %H:%M:%S"
  return os.date(format_str, M.parse_datetime(datetime_str))
end

---Sorts table of tasks by specified column
---@param tasks table Table of tasks
---@param column string Column name to sort by
---@param order string|nil Sort order ("asc" or "desc", default: "desc")
function M.sort_by_column(tasks, column, order)
  order = order or "desc"
  table.sort(tasks, function(a, b)
    if order == "desc" then
      return a[column] > b[column]
    else
      return a[column] < b[column]
    end
  end)
end

return M
```

# taskforge.nvim/plugin/
taskforge.nvim/plugin//taskforge.lua
```lua
require("taskforge")
```


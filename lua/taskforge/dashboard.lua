-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
local M = {}

local utils = require("taskforge.utils")
local config = require("taskforge.config")

-- Safely load the interface module
local interface = nil
local ok_interface = pcall(function()
  interface = require("taskforge.interface")
end)

local project_tasks = {}
local other_tasks = {}

-- Debug function - write to log file if debug enabled
local function debug_log(msg, data)
  local cfg = config.get()
  if cfg.debug and cfg.debug.enable then
    utils.debug_log("DASHBOARD", msg, data)
  end
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
  elseif which == "normal" then
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
  if config.get().highlights and config.get().highlights.urgent and config.get().highlights.urgent.group then
    hl_urgent = config.get().highlights.urgent.group
  else
    hl_urgent = get_default_hl_group("urgent")
  end
  if hl_urgent then
    vim.api.nvim_set_hl(0, "TFDashboardHeaderUrgent", hl_urgent)
  end
  local hl_not_urgent = nil

  if config.get().highlights and config.get().highlights.normal and config.get().highlights.normal.group then
    hl_not_urgent = config.get().highlights.normal.group
  else
    hl_not_urgent = get_default_hl_group("normal")
  end
  if hl_not_urgent then
    vim.api.nvim_set_hl(0, "TFDashboardHeader", hl_not_urgent)
  end
end

local function hl_tasks()
  debug_log("Highlighting tasks")
  setup_hl_groups()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, line in ipairs(lines) do
    if utils.in_table(project_tasks, line) then
      vim.api.nvim_buf_add_highlight(0, -1, "TFDashboardHeaderUrgent", i - 1, 0, -1)
    elseif utils.in_table(other_tasks, line) then
      vim.api.nvim_buf_add_highlight(0, -1, "TFDashboardHeader", i - 1, 0, -1)
    end
  end
end

function M.create_section()
  debug_log("Creating dashboard section")

  -- Check if dashboard feature is enabled
  local cfg = config.get().dashboard
  if not cfg or not cfg.snacks_options or cfg.snacks_options.enable == false then
    debug_log("Dashboard disabled in config")
    return {}
  end

  debug_log("Dashboard config", cfg)

  local title = {
    icon = cfg.snacks_options.icon or "",
    title = cfg.snacks_options.title or "Tasks",
    pane = cfg.snacks_options.pane or 1,
  }

  if cfg.snacks_options.key and cfg.snacks_options.action then
    debug_log("Setting up action", { key = cfg.snacks_options.key, action = cfg.snacks_options.action })

    if cfg.snacks_options.action == "taskwarrior-tui" and ok_interface and interface then
      title.action = function()
        interface.open_tt()
      end
    elseif cfg.snacks_options.action == "project" then
      title.action = function()
        -- TODO: hook the project view
      end
    elseif cfg.snacks_options.action == "tasks" then
      title.action = function()
        -- TODO: hook the overall view
      end
    end

    if title.action then
      title.key = cfg.snacks_options.key
    end
  end

  local items = M.get_snacks_items()
  debug_log("Retrieved items count", #items)

  local section = {
    pane = cfg.snacks_options.pane or 1,
    padding = cfg.snacks_options.padding or 1,
    indent = cfg.snacks_options.indent or 3,
    text = items,
  }

  section.height = cfg.snacks_options.height and math.max(cfg.snacks_options.height, #section.text) or #section.text

  debug_log("Section setup", { pane = section.pane, height = section.height, items = #section.text })

  -- Setup autocmd to catch Snacks.Dashboard events
  vim.api.nvim_create_autocmd("User", {
    pattern = "SnacksDashboardLoaded",
    callback = hl_tasks,
  })

  return { title, section }
end

function M.get_snacks_items()
  debug_log("Getting Snacks items")

  -- Get tasks from the tasks module
  local tasks_result
  local ok, err = pcall(function()
    tasks_result = require("taskforge.tasks").get_dashboard_tasks()
  end)

  if not ok then
    debug_log("Error getting dashboard tasks", err)
    utils.notify("Failed to get dashboard tasks: " .. tostring(err), vim.log.levels.ERROR)
    return {}
  end

  if not tasks_result then
    debug_log("No tasks data returned")
    return {}
  end

  debug_log("Tasks data", {
    project_tasks = #(tasks_result.project_tasks or {}),
    other_tasks = #(tasks_result.other_tasks or {}),
  })

  return M.process_tasks_for_snacks(tasks_result.project_tasks or {}, tasks_result.other_tasks or {})
end

--- Format tasks for Snacks dashboard
--- @param project_tasks table
--- @param other_tasks table
--- @return table[]
function M.process_tasks_for_snacks(project_tasks, other_tasks)
  debug_log("Processing tasks", {
    project_count = #project_tasks,
    other_count = #other_tasks,
  })

  local items = {}
  local current_project = require("taskforge.project").current()

  if current_project then
    debug_log("Current project", current_project)
    table.insert(
      items,
      { current_project, hl = "dir", width = config.get().dashboard.format.max_width - 1, align = "center" }
    )
    table.insert(items, { "\n", hl = "dir" })
  end

  -- Add project tasks
  for _, task in ipairs(project_tasks) do
    table.insert(items, M.create_snacks_item(task))
  end

  -- Add separator if both types exist
  if #project_tasks > 0 and #other_tasks > 0 then
    table.insert(items, { "--+--", hl = "dir", width = config.get().dashboard.format.max_width - 1, align = "center" })
  end

  -- Add other tasks
  for _, task in ipairs(other_tasks) do
    table.insert(items, M.create_snacks_item(task))
  end

  debug_log("Processed items count", #items)
  return items
end

--- Create single Snacks dashboard item
--- @param task table
--- @return table
function M.create_snacks_item(task)
  local cfg = config.get()
  debug_log("Creating item for task", { id = task.id, description = task.description })

  local formatted = M.format_task_line(task, cfg.dashboard.format)
  local highlight = "normal"

  if
    task.urgency
    and cfg.highlights
    and cfg.highlights.urgent
    and cfg.highlights.urgent.threshold
    and tonumber(task.urgency) >= cfg.highlights.urgent.threshold
  then
    highlight = "special"
  end

  return {
    text = formatted,
    hl = highlight,
  }
end

--- Format task line according to dashboard config
--- @param task table
--- @param fmt_config table
--- @return string
function M.format_task_line(task, fmt_config)
  local parts = {}

  -- Ensure column_widths is initialized
  fmt_config.column_widths = fmt_config.column_widths
    or {
      project = 12,
      description = 30,
      due = 10,
      urgency = 5,
    }

  for _, col in ipairs(fmt_config.columns) do
    local val = task[col] or ""
    if col == "project" then
      val = utils.replace_project_name(val, fmt_config)
    end

    local width = fmt_config.column_widths[col] or 10
    table.insert(parts, string.format("%-" .. width .. "s", val))
  end

  return table.concat(parts, " ")
end

return M

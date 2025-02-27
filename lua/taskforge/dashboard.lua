-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
local M = {}

local utils = require("taskforge.utils")
local config = require("taskforge.contig")
local interface = require("taskforge.interface")
local project_tasks = {}
local other_tasks = {}

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
  setup_hl_groups()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  -- log()
  for i, line in ipairs(lines) do
    if utils.in_table(project_tasks, line) then
      vim.api.nvim_buf_add_highlight(0, -1, "TFDashboardHeaderUrgent", i - 1, 0, -1)
    elseif utils.in_table(other_tasks, line) then
      vim.api.nvim_buf_add_highlight(0, -1, "TFDashboardHeader", i - 1, 0, -1)
    end
  end
end

function M.create_section()
  -- log()
  local title = {
    icon = config.get().dashboard.snacks_options.icon,
    title = config.get().dashboard.snacks_options.title,
    pane = config.get().dashboard.snacks_options.pane or 1,
  }
  if config.get().dashboard.snacks_options.key ~= nil and config.get().dashboard.snacks_options.action ~= nil then
    if config.get().dashboard.snacks_options.action == "taskwarrior-tui" then
      title.action = function()
        interface.open_tt()
      end
    elseif config.get().dashboard.snacks_options.action == "project" then
      title.action = function()
        -- TODO: hook the project view
      end
    elseif config.get().dashboard.snacks_options.action == "tasks" then
      title.action = function()
        -- TODO: hook the overall view
      end
    end
    if title.action then
      title.key = config.get().dashboard.snacks_options.key
    end
  end
  local section = {
    pane = config.get().dashboard.snacks_options.pane or 1,
    padding = config.get().dashboard.snacks_options.padding,
    indent = config.get().dashboard.snacks_options.indent,
    text = M.get_snacks_items(),
  }
  section.height = config.get().dashboard.snacks_options.height
      and math.max(config.get().dashboard.snacks_options.height, #section.text)
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

function M.get_snacks_items()
  local ok, tasks = pcall(function()
    return require("taskforge.tasks").get_dashboard_tasks()
  end)

  if not ok or not tasks then
    vim.notify("Failed to get dashboard tasks", vim.log.levels.ERROR)
    return {}
  end

  return M.process_tasks_for_snacks(tasks.project_tasks, tasks.other_tasks)
end

--- Format tasks for Snacks dashboard
--- @param project_tasks table
--- @param other_tasks table
--- @return table[]
function M.process_tasks_for_snacks(project_tasks, other_tasks)
  local items = {}

  if M.project ~= nil then
    table.insert(
      items,
      { M.project, hl = "dir", width = config.get().dashboard.format.max_width - 1, align = "center" }
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

  return items
end

--- Create single Snacks dashboard item
--- @param task table
--- @return table
function M.create_snacks_item(task)
  local formatted = M.format_task_line(task, config.get().dashboard.format)
  local highlight
  if
    task.urgency ~= nil
    and config.get().highlights.urgent.threshold ~= nil
    and tonumber(task.urgency) >= config.get().highlights.urgent.threshold
  then
    highlight = "special"
  else
    highlight = "normal"
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
  for _, col in ipairs(fmt_config.columns) do
    local val = task[col] or ""
    if col == "project" then
      val = utils.replace_project_name(val, fmt_config)
    end
    table.insert(parts, string.format("%-" .. fmt_config.column_widths[col] .. "s", val))
  end
  return table.concat(parts, " ")
end

return M

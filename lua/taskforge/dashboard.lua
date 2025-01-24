-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
local M = {}

local utils = require("taskforge.utils.utils")
local tw_interface = require("taskforge.tw-interface")
local project = require("taskforge.project")
local config = require("taskforge.config")
local api = vim.api

local urgent_tasks = {}
local non_urgent_tasks = {}

local function parse_task(task_to_parse, columnsWidth)
  local task = {}
  for _, column in ipairs(config.options.dashboard.format.columns) do
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
          task[k] = utils.replace_project_name(v, config.options.dashboard.format)
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
  local max_width = maxwidth or config.options.dashboard.format.max_width
  local needed_for_padding = #config.options.dashboard.format.columns
  local total_width = 0
  sanitize_tasks(task_list)
  sanitize_tasks(other_tasks)
  for _, column in ipairs(config.options.dashboard.format.columns) do
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
  local main_tasks = tw_interface.tasks_get_urgent(config.options.dashboard.format.limit, M.project)
  local other_tasks = {}
  if
    M.project ~= nil
    and config.options.dashboard.format.non_project_limit ~= nil
    and config.options.dashboard.format.non_project_limit > 0
  then
    other_tasks = tw_interface.tasks_get_urgent(config.options.dashboard.format.non_project_limit, M.project, true)
  end
  return main_tasks, other_tasks
end

function M.format_tasks(max_width)
  local lines = {}
  local task_list, other_tasks = M.get_tasks()
  local columnsWidth = get_columns_width(task_list, other_tasks, max_width)

  for _, task in ipairs(task_list) do
    local line = parse_task(task, columnsWidth)
    if
      task.urgency ~= nil
      and config.options.highlights.urgent.threshold ~= nil
      and tonumber(task.urgency) >= config.options.highlights.urgent.threshold
    then
      table.insert(urgent_tasks, line)
    else
      table.insert(non_urgent_tasks, line)
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
      and config.options.highlights.urgent.threshold ~= nil
      and tonumber(task.urgency) >= config.options.highlights.urgent.threshold
    then
      table.insert(urgent_tasks, line)
    else
      table.insert(non_urgent_tasks, line)
    end
    table.insert(lines, line)
  end
  return lines
end

function M.process_tasks_for_snacks()
  local max_width = config.options.dashboard.format.max_width - config.options.dashboard.snacks_options.indent
  local hl_normal = "dir"
  local hl_overdue = "special"
  local lines = {}
  local task_list, other_tasks = M.get_tasks()
  local columnsWidth = get_columns_width(task_list, other_tasks, max_width)

  for _, task in ipairs(task_list) do
    local line = parse_task(task, columnsWidth)
    local hl = hl_normal
    if
      task.urgency ~= nil
      and config.options.highlights.urgent.threshold ~= nil
      and tonumber(task.urgency) >= config.options.highlights.urgent.threshold
    then
      table.insert(urgent_tasks, line)
      hl = hl_overdue
    else
      table.insert(non_urgent_tasks, line)
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
      and config.options.highlights.urgent.threshold ~= nil
      and tonumber(task.urgency) >= config.options.highlights.urgent.threshold
    then
      table.insert(urgent_tasks, line)
      hl = hl_overdue
    else
      table.insert(non_urgent_tasks, line)
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
    local hl = api.nvim_get_hl(0, { name = "@keyword" })
    return {
      bg = hl.bg,
      fg = hl.fg,
      cterm = hl.cterm,
      bold = hl.bold,
      italic = hl.italic,
      reverse = hl.reverse,
    }
  elseif which == "not_urgent" then
    local hl = api.nvim_get_hl(0, { name = "Comment" })
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
  if config.options.highlights and config.options.highlights.urgent and config.options.highlights.urgent.group then
    hl_urgent = config.options.highlights.urgent.group
  else
    hl_urgent = get_default_hl_group("urgent")
  end
  if hl_urgent then
    api.nvim_set_hl(0, "TFDashboardHeaderUrgent", hl_urgent)
  end
  local hl_not_urgent = nil

  if config.options.highlights and config.options.highlights.normal and config.options.highlights.normal.group then
    hl_not_urgent = config.options.highlights.normal.group
  else
    hl_not_urgent = get_default_hl_group("not_urgent")
  end
  if hl_not_urgent then
    api.nvim_set_hl(0, "TFDashboardHeader", hl_not_urgent)
  end
end

local function hl_tasks()
  setup_hl_groups()
  local lines = api.nvim_buf_get_lines(0, 0, -1, false)
  -- log()
  log("Lines: " .. vim.inspect(urgent_tasks))
  for i, line in ipairs(lines) do
    if utils.in_table(urgent_tasks, line) then
      api.nvim_buf_add_highlight(0, -1, "TFDashboardHeaderUrgent", i - 1, 0, -1)
    elseif utils.in_table(non_urgent_tasks, line) then
      api.nvim_buf_add_highlight(0, -1, "TFDashboardHeader", i - 1, 0, -1)
    end
  end
end

function M.get_snacks_dashboard_tasks()
  -- log()
  local title = {
    icon = config.options.dashboard.snacks_options.icon,
    title = config.options.dashboard.snacks_options.title,
    pane = config.options.dashboard.snacks_options.pane or 1,
  }
  if config.options.dashboard.snacks_options.key ~= nil and config.options.dashboard.snacks_options.action ~= nil then
    if config.options.dashboard.snacks_options.action == "taskwarrior-tui" then
      title.action = function()
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
    elseif config.options.dashboard.snacks_options.action == "project" then
      title.action = function()
        -- TODO: hook the project view
      end
    elseif config.options.dashboard.snacks_options.action == "tasks" then
      title.action = function()
        -- TODO: hook the overall view
      end
    end
    title.key = config.options.dashboard.snacks_options.key
  end
  local section = {
    pane = config.options.dashboard.snacks_options.pane or 1,
    padding = config.options.dashboard.snacks_options.padding,
    indent = config.options.dashboard.snacks_options.indent,
    text = M.process_tasks_for_snacks(),
  }
  section.height = config.options.dashboard.snacks_options.height
      and math.max(config.options.dashboard.snacks_options.height, #section.text)
    or #section.text

  -- setup autocmd to catch Snacks.Dashboard events, for reference here they are:
  --  SnacksDashboardOpened
  --  SnacksDashboardClosed
  --  SnacksDashboardUpdatePre
  --  SnacksDashboardUpdatePost
  --  SncaksDashboardUpdate

  api.nvim_create_autocmd("User", {
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

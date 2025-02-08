-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
local M = {}
local config = require("taskforge.utils.config")
local cache = require("taskforge.utils.cache")
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
  return utils.exec(cmd, args, opts, process_tasks)
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

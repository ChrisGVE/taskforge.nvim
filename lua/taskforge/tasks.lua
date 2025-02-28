-- Taskwarrior integration layer
-- Handles task CRUD operations and caching

local M = {}
---@type Job
local Job = require("plenary.job")
local utils = require("taskforge.utils")
local config = require("taskforge.config")

function M.setup()
  M._cache = {
    tasks = {},
    valid = false,
    timestamp = nil,
  }
  -- Initialize with an empty cache
  M.refresh_cache()
end

-- Get tasks for dashboard
function M.get_dashboard_tasks()
  if not M._cache.valid then
    M.refresh_cache()
  end

  -- Add debug logging if debug is enabled
  local cfg = config.get()
  if cfg.debug and cfg.debug.enable then
    local count = M._cache.tasks and #M._cache.tasks or 0
    utils.debug_log("TASKS", "Retrieved " .. count .. " tasks from cache")
  end

  -- Split into project/other tasks
  local current_project = nil
  local project_module = require("taskforge.project")
  if project_module and project_module.current then
    current_project = project_module.current()
  end

  local project_tasks = {}
  local other_tasks = {}

  for _, task in ipairs(M._cache.tasks or {}) do
    if task.project == current_project then
      table.insert(project_tasks, task)
    else
      table.insert(other_tasks, task)
    end
  end

  -- Sort by urgency (higher values first)
  utils.sort_by_column(project_tasks, "urgency", "desc")
  utils.sort_by_column(other_tasks, "urgency", "desc")

  -- Apply limits if configured
  local format_config = cfg.dashboard and cfg.dashboard.format or {}
  local project_limit = format_config.limit or 5
  local other_limit = format_config.non_project_limit or 5

  if #project_tasks > project_limit then
    project_tasks = utils.slice(project_tasks, 1, project_limit)
  end

  if #other_tasks > other_limit then
    other_tasks = utils.slice(other_tasks, 1, other_limit)
  end

  return {
    project_tasks = project_tasks,
    other_tasks = other_tasks,
  }
end

-- Configure Taskwarrior settings
function M.configure()
  utils.debug_log("TASKS", "Configuring taskwarrior")

  local job = require("plenary.job")
  local cmds = {
    { "task", "config", "rc.editor", "nvim" },
    { "task", "config", "rc.confirmation", "off" },
    { "task", "config", "rc.verbose", "no" },
  }

  for _, cmd in ipairs(cmds) do
    job
      :new({
        command = cmd[1],
        args = { cmd[2], cmd[3], cmd[4] },
        on_exit = function(j, return_code)
          if return_code ~= 0 then
            utils.debug_log("TASKS", "Failed to configure taskwarrior", {
              cmd = cmd[2] .. " " .. cmd[3] .. " " .. cmd[4],
              error = table.concat(j:stderr_result(), "\n"),
            })
          end
        end,
      })
      :start()
  end
  utils.notify("Taskwarrior configured for taskforge")
end

-- Get all tasks
function M.list()
  if not M._cache.valid then
    M.refresh_cache()
  end
  return M._cache.tasks
end

-- Get tasks with annotations
function M.list_with_annotations()
  if not M._cache.valid then
    M.refresh_cache()
  end

  -- Filter to tasks that have annotations
  local tasks_with_annotations = {}
  for _, task in ipairs(M._cache.tasks or {}) do
    if task.annotations and #task.annotations > 0 then
      table.insert(tasks_with_annotations, task)
    end
  end

  return tasks_with_annotations
end

-- Get a specific task by UUID
function M.get_task(uuid)
  -- First check cache
  for _, task in ipairs(M._cache.tasks or {}) do
    if task.uuid == uuid then
      return task
    end
  end

  -- Not in cache, try to fetch directly
  local result = nil
  Job:new({
    command = "task",
    args = { uuid, "export" },
    on_exit = function(j, code)
      if code == 0 then
        local output = table.concat(j:result(), "\n")
        if output and output ~= "" then
          local ok, data = pcall(vim.json.decode, output)
          if ok and data and #data > 0 then
            result = data[1]
          end
        end
      end
    end,
  }):sync()

  return result
end

-- Refresh task cache (asynchronous version)
function M.refresh_cache()
  -- Check if taskwarrior is installed
  if vim.fn.executable("task") ~= 1 then
    utils.debug_log("TASKS", "Taskwarrior is not installed or not in PATH")
    return
  end

  -- Try to export tasks with async approach
  local output = {}
  local error_output = {}

  Job:new({
    command = "task",
    args = { "export" },
    on_stdout = function(_, data)
      table.insert(output, data)
    end,
    on_stderr = function(_, data)
      table.insert(error_output, data)
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        utils.debug_log("TASKS", "Task export failed", table.concat(error_output, "\n"))
        return
      end

      local data = table.concat(output, "\n")
      if data == "" then
        -- No tasks found
        M._cache = {
          tasks = {},
          valid = true,
          timestamp = os.time(),
        }
        utils.debug_log("TASKS", "No tasks found in taskwarrior")
        return
      end

      local ok, tasks = pcall(vim.json.decode, data)
      if ok then
        M._cache = {
          tasks = tasks,
          valid = true,
          timestamp = os.time(),
        }
        utils.debug_log("TASKS", "Refreshed task cache", #tasks)
      else
        utils.debug_log("TASKS", "Failed to parse task data", tasks)
      end
    end,
  }):start() -- Use start() instead of sync() to make it asynchronous
end

-- Create a new task
function M.create(description, opts, callback)
  opts = opts or {}
  local args = { "add", description }

  if opts.project then
    table.insert(args, "project:" .. opts.project)
  end

  if opts.priority then
    table.insert(args, "priority:" .. opts.priority)
  end

  if opts.due then
    table.insert(args, "due:" .. opts.due)
  end

  if opts.tags and #opts.tags > 0 then
    for _, tag in ipairs(opts.tags) do
      table.insert(args, "+" .. tag)
    end
  end

  -- No longer adding annotation during task creation

  utils.debug_log("TASKS", "Creating task", {
    description = description,
    args = args,
  })

  -- Output will have the task ID/UUID
  local task_output = {}

  Job:new({
    command = "task",
    args = args,
    on_stdout = function(_, data)
      table.insert(task_output, data)
    end,
    on_exit = function(j, code)
      if code == 0 then
        -- Extract UUID from output
        local uuid = nil
        for _, line in ipairs(task_output) do
          local id = line:match("Created task ([0-9a-f%-]+)")
          if id then
            uuid = id
            break
          end
        end

        utils.debug_log("TASKS", "Task created", { uuid = uuid, description = description })

        -- Add annotation separately if file and line are provided
        if uuid and opts.file and opts.line then
          local uri = string.format("file://%s:%d", opts.file, opts.line)
          -- Add annotation in a separate step
          M.annotate(uuid, uri, function()
            utils.notify("Task created: " .. description)
            -- Refresh cache after annotation is added
            M.refresh_cache()

            -- Call callback with UUID if provided
            if callback then
              vim.defer_fn(function()
                callback(uuid)
              end, 10)
            end
          end)
        else
          utils.notify("Task created: " .. description)
          -- No annotation needed, just refresh cache
          M.refresh_cache()

          -- Call callback with UUID if provided
          if callback and uuid then
            vim.defer_fn(function()
              callback(uuid)
            end, 10)
          end
        end
      else
        local err = table.concat(j:stderr_result(), "\n")
        utils.debug_log("TASKS", "Failed to create task", err)
        utils.notify("Failed to create task: " .. err, vim.log.levels.ERROR)

        if callback then
          vim.defer_fn(function()
            callback(nil)
          end, 10)
        end
      end
    end,
  }):start()
end

-- Open URI
function M.open_uri(uri)
  local path, lnum_str = uri:match("file://(.*):(%d+)")
  if path and lnum_str then
    vim.cmd("edit " .. path)
    local lnum = tonumber(lnum_str) or 1 -- Ensure we have a valid integer
    vim.fn.cursor(lnum, 1)
    utils.debug_log("TASKS", "Opened file from URI", path .. ":" .. lnum_str)
  else
    utils.debug_log("TASKS", "Invalid URI format", uri)
  end
end

-- Mark a task as done
function M.done(uuid)
  if not uuid then
    utils.debug_log("TASKS", "No task UUID provided")
    return
  end

  utils.debug_log("TASKS", "Marking task as done", uuid)

  Job:new({
    command = "task",
    args = { uuid, "done" },
    on_exit = function(j, code)
      if code == 0 then
        -- Task marked as done, refresh cache
        M.refresh_cache()

        -- Notify tracker module about status change
        local tracker = require("taskforge.tracker")
        if tracker and tracker.handle_task_status_change then
          vim.schedule(function()
            tracker.handle_task_status_change(uuid, "completed")
          end)
        end

        utils.notify("Task marked as done")
      else
        local err = table.concat(j:stderr_result(), "\n")
        utils.debug_log("TASKS", "Failed to mark task as done", err)
        utils.notify("Failed to mark task as done: " .. err, vim.log.levels.ERROR)
      end
    end,
  }):start()
end

-- Delete a task
function M.delete(uuid)
  if not uuid then
    utils.debug_log("TASKS", "No task UUID provided")
    return
  end

  utils.debug_log("TASKS", "Deleting task", uuid)

  Job:new({
    command = "task",
    args = { uuid, "delete" },
    on_exit = function(j, code)
      if code == 0 then
        M.refresh_cache()

        -- Notify tracker module about deletion
        local tracker = require("taskforge.tracker")
        if tracker and tracker.handle_task_status_change then
          tracker.handle_task_status_change(uuid, "deleted")
        end

        utils.notify("Task deleted")
      else
        local err = table.concat(j:stderr_result(), "\n")
        utils.debug_log("TASKS", "Failed to delete task", err)
        utils.notify("Failed to delete task: " .. err, vim.log.levels.ERROR)
      end
    end,
  }):start()
end

-- Add annotation to a task
function M.annotate(uuid, annotation)
  if not uuid or not annotation then
    utils.debug_log("TASKS", "UUID and annotation required")
    return
  end

  utils.debug_log("TASKS", "Adding annotation", { uuid = uuid, annotation = annotation })

  Job:new({
    command = "task",
    args = { uuid, "annotate", annotation },
    on_exit = function(j, code)
      if code == 0 then
        M.refresh_cache()
        utils.notify("Annotation added")
      else
        local err = table.concat(j:stderr_result(), "\n")
        utils.debug_log("TASKS", "Failed to add annotation", err)
        utils.notify("Failed to add annotation: " .. err, vim.log.levels.ERROR)
      end
    end,
  }):start()
end

-- Handle file rename
function M.handle_file_rename(old_path, new_path)
  utils.debug_log("TASKS", "Handling file rename", { old = old_path, new = new_path })

  -- Get tasks with annotations
  local tasks_with_annotations = M.list_with_annotations()

  for _, task in ipairs(tasks_with_annotations) do
    if task.annotations then
      for i, anno in ipairs(task.annotations) do
        -- Look for file:// annotations with old path
        local uri = anno.description:match("file://([^%s]+)")
        if uri and uri:match("^" .. old_path:gsub("%-", "%%-") .. ":%d+$") then
          -- This annotation points to the old file
          local line = uri:match(":(%d+)$")
          local new_uri = "file://" .. new_path .. ":" .. line

          -- Update the annotation
          M.modify_annotation(task.uuid, i, new_uri)
          break
        end
      end
    end
  end
end

-- Modify an annotation
function M.modify_annotation(uuid, index, new_text)
  utils.debug_log("TASKS", "Modifying annotation", { uuid = uuid, index = index, new_text = new_text })

  Job:new({
    command = "task",
    args = { uuid, "denotate", tostring(index) },
    on_exit = function(j, code)
      if code == 0 then
        -- Annotation removed, add new one
        M.annotate(uuid, new_text, function()
          -- Refresh cache after the annotation is modified
          M.refresh_cache()
        end)
      else
        local err = table.concat(j:stderr_result(), "\n")
        utils.debug_log("TASKS", "Failed to remove annotation", err)
      end
    end,
  }):start()
end

-- Jump to task location in file
function M.jump_to_task(uuid)
  utils.debug_log("TASKS", "Jumping to task", uuid)

  -- Let tracker handle this
  local tracker = require("taskforge.tracker")
  if tracker and tracker.jump_to_task then
    return tracker.jump_to_task(uuid)
  end

  -- Fallback: try to find annotation with file:// URI
  local task = M.get_task(uuid)
  if task and task.annotations then
    for _, anno in ipairs(task.annotations) do
      if type(anno.description) == "string" and anno.description:match("file://") then
        local uri = anno.description
        M.open_uri(uri)
        return true
      end
    end
  end

  utils.notify("No file location found for task", vim.log.levels.WARN)
  return false
end

return M

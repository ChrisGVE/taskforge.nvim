-- Taskwarrior integration layer
-- Handles task CRUD operations and caching

local M = {}
local Job = require("plenary.job")
local utils = require("taskforge.utils")
local config = require("taskforge.config")

function M.setup()
  M._cache = {
    tasks = {},
    valid = false,
    timestamp = nil,
  }
end

function M.get_dashboard_tasks()
  if not M._cache.valid then
    M.refresh_cache()
  end

  -- Add debug logging
  vim.notify("Retrieved " .. #M._cache.tasks .. " tasks from cache", vim.log.levels.DEBUG)

  -- Split into project/other tasks
  local current_project = require("taskforge.project").current()
  local project_tasks = {}
  local other_tasks = {}

  for _, task in ipairs(M._cache.tasks) do
    if task.project == current_project then
      table.insert(project_tasks, task)
    else
      table.insert(other_tasks, task)
    end
  end

  return {
    project_tasks = project_tasks,
    other_tasks = other_tasks,
  }
end

function M.configure()
  local job = require("plenary.job")
  local cmds = {
    { "task", "config", "rc.editor", "nvim" },
    { "task", "config", "rc.confirmation", "off" },
    { "task", "config", "rc.verbose", "no" },
  }

  for _, cmd in ipairs(cmds) do
    job:new({ command = cmd[1], args = { cmd[2], cmd[3], cmd[4] } }):sync()
  end
  vim.notify("taskwarrior configured for taskforge")
end

function M.list()
  if not M._cache.valid then
    M.refresh_cache()
  end
  return M._cache.tasks
end

function M.refresh_cache()
  Job:new({
    command = "task",
    args = { "export" },
    on_exit = function(j, code)
      if code ~= 0 then
        utils.notify("Task export failed: " .. table.concat(j:stderr_result(), "\n"), vim.log.levels.ERROR)
        return
      end

      local ok, tasks = pcall(vim.json.decode, table.concat(j:result(), "\n"))
      if ok then
        M._cache = {
          tasks = tasks,
          valid = true,
          timestamp = os.time(),
        }
      end
    end,
  }):sync()
end

function M.create(description, opts)
  -- Add annotation with file URI
  local uri = string.format("file://%s:%d", vim.fn.expand("%:p"), vim.fn.line("."))
  task.annotations = task.annotations or {}
  table.insert(task.annotations, uri)
  opts = opts or {}
  local args = { "add", description }

  if opts.project then
    table.insert(args, "project:" .. opts.project)
  end

  Job:new({
    command = "task",
    args = args,
    on_exit = function(j, code)
      if code == 0 then
        M.refresh_cache()
        utils.notify("Task created: " .. description)
      end
    end,
  }):start()
end

function M.open_uri(uri)
  local path, lnum = uri:match("file://(.*):(%d+)")
  vim.cmd("edit " .. path)
  vim.fn.cursor(lnum, 1)
end

return M

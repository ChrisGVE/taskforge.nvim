-- lua/taskforge/tracker/core.lua
-- Core tracker functionality and state management

local M = {}
local config = require("taskforge.config")
local debug = require("taskforge.debug")
local debounce_ms = 500

-- Add initialization function for buffer tracking
function M.initialize_buffer_tracking(bufnr)
  if not M.state.buf_cache[bufnr] then
    M.state.buf_cache[bufnr] = {
      tags = {},
      changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
      processed = false,
      batch_processed = false, -- Track if buffer had batch processing
    }
  end
end

-- Add function to mark a buffer as batch processed
function M.set_buffer_batch_processed(bufnr)
  if not M.state.buf_cache[bufnr] then
    M.initialize_buffer_tracking(bufnr)
  end

  M.state.buf_cache[bufnr].batch_processed = true
end

-- Add function to check if buffer was batch processed
function M.is_buffer_batch_processed(bufnr)
  return M.state.buf_cache[bufnr] and M.state.buf_cache[bufnr].batch_processed
end

-- Core state
M.state = {
  buf_cache = {}, -- Buffer-specific cache
  task_cache = {}, -- Cache of task UUIDs to location
  debounce_timers = {}, -- Timers for debouncing
  last_change = {}, -- Timestamp of last change per buffer
}

-- Constants
M.constants = {
  -- UUID pattern for task identification in comments
  uuid_pattern = "%[task:([0-9a-f%-]+)%]",
  -- Pattern for opted-out comments that should not be tracked
  optout_pattern = "%[notrack%]",
}

-- Initialize core module
function M.setup()
  -- Load tasks from taskwarrior
  M._load_tasks()

  -- Get debounce setting from config
  debounce_ms = config.get().tags.debounce or 500
end

-- Load existing tasks from taskwarrior
function M._load_tasks()
  local tasks = require("taskforge.tasks")

  -- Try to get tasks with annotations that have file paths
  local all_tasks = tasks.list_with_annotations()

  for _, task in ipairs(all_tasks) do
    if task.annotations then
      for _, anno in ipairs(task.annotations) do
        -- Look for file:// annotations
        local file_uri = anno.description:match("file://([^%s]+)")
        if file_uri then
          local path, line = file_uri:match("([^:]+):(%d+)")
          if path and line then
            -- Store in task cache
            M.state.task_cache[task.uuid] = {
              file = path,
              line = tonumber(line),
              description = task.description,
              status = task.status,
            }
          end
        end
      end
    end
  end

  debug.log("TRACKER", "Loaded task cache", #vim.tbl_keys(M.state.task_cache))
end

-- Reset the debounce timer for a buffer
function M.reset_debounce_timer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Cancel previous timer if it exists
  if M.state.debounce_timers[bufnr] then
    vim.loop.timer_stop(M.state.debounce_timers[bufnr])
    M.state.debounce_timers[bufnr] = nil
  end

  -- Update timestamp of last change
  M.state.last_change[bufnr] = vim.loop.now()

  -- Create new timer
  M.state.debounce_timers[bufnr] = vim.defer_fn(function()
    -- Check if enough time has passed since the last edit
    local time_since_change = vim.loop.now() - (M.state.last_change[bufnr] or 0)
    local tracker = require("taskforge.tracker")

    if not tracker.state.edit_active or time_since_change > debounce_ms then
      -- Process buffer when editing has stopped for a while
      local buffer = require("taskforge.tracker.buffer")
      buffer.process(bufnr, false) -- false = not initial processing
      M.state.debounce_timers[bufnr] = nil
    end
  end, debounce_ms)
end

-- Clean up resources for a buffer
function M.cleanup_buffer(bufnr)
  -- Clear any debounce timer
  if M.state.debounce_timers[bufnr] then
    vim.loop.timer_stop(M.state.debounce_timers[bufnr])
    M.state.debounce_timers[bufnr] = nil
  end

  -- Clear buffer cache
  M.state.buf_cache[bufnr] = nil

  -- Remove last change timestamp
  M.state.last_change[bufnr] = nil
end

-- Get a task by UUID
function M.get_task(uuid)
  return M.state.task_cache[uuid]
end

-- Update task location information
function M.update_task_location(uuid, file, line)
  if M.state.task_cache[uuid] then
    M.state.task_cache[uuid].file = file
    M.state.task_cache[uuid].line = line
  else
    M.state.task_cache[uuid] = {
      file = file,
      line = line,
      status = "pending",
    }
  end
end

-- Get tasks for a buffer
function M.get_tasks_for_buffer(bufnr)
  local tasks = {}
  local file_path = vim.api.nvim_buf_get_name(bufnr)

  for uuid, location in pairs(M.state.task_cache) do
    if location.file == file_path then
      table.insert(tasks, {
        uuid = uuid,
        line = location.line,
        description = location.description,
        status = location.status,
      })
    end
  end

  return tasks
end

-- Check if a buffer has been modified since last processing
function M.buffer_modified_since_last_process(bufnr)
  if not M.state.buf_cache[bufnr] then
    return true
  end

  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  return changedtick ~= M.state.buf_cache[bufnr].changedtick
end

-- Set buffer processed state
function M.set_buffer_processed(bufnr)
  if not M.state.buf_cache[bufnr] then
    M.state.buf_cache[bufnr] = {}
  end

  M.state.buf_cache[bufnr].changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  M.state.buf_cache[bufnr].processed = true
end

-- Helper function to escape pattern special characters
function M.escape_pattern(text)
  return text:gsub("[%%%(%)%.%[%]%*%+%-%?%^%$]", "%%%1")
end

-- Get the current config
function M.get_config()
  return config.get()
end

-- Cache tag information for a buffer line
function M.cache_tag(bufnr, lnum, data)
  if not M.state.buf_cache[bufnr] then
    M.state.buf_cache[bufnr] = {
      tags = {},
    }
  end

  M.state.buf_cache[bufnr].tags = M.state.buf_cache[bufnr].tags or {}
  M.state.buf_cache[bufnr].tags[lnum] = data
end

-- Get cached tag information
function M.get_cached_tag(bufnr, lnum)
  if not M.state.buf_cache[bufnr] or not M.state.buf_cache[bufnr].tags then
    return nil
  end

  return M.state.buf_cache[bufnr].tags[lnum]
end

-- Get all cached tags for a buffer
function M.get_all_cached_tags(bufnr)
  if not M.state.buf_cache[bufnr] or not M.state.buf_cache[bufnr].tags then
    return {}
  end

  return M.state.buf_cache[bufnr].tags
end

-- Clear cached tags for a buffer
function M.clear_cached_tags(bufnr)
  if M.state.buf_cache[bufnr] then
    M.state.buf_cache[bufnr].tags = {}
  end
end

-- Check if a buffer has been processed before
function M.is_buffer_processed(bufnr)
  return M.state.buf_cache[bufnr] and M.state.buf_cache[bufnr].processed
end

-- Get the namespace for extmarks
function M.get_namespace()
  return vim.api.nvim_create_namespace("taskforge_tags")
end

-- Register a task for tracking
function M.register_task(uuid, file, line, description, status)
  M.state.task_cache[uuid] = {
    file = file,
    line = line,
    description = description,
    status = status or "pending",
  }
end

-- Unregister a task from tracking
function M.unregister_task(uuid)
  M.state.task_cache[uuid] = nil
end

-- Verify a comment line contains a valid UUID format
function M.verify_uuid_format(line, uuid)
  local original_marker = "[task:" .. uuid .. "]"
  local escaped_marker = M.escape_pattern(original_marker)

  return line:match(escaped_marker) ~= nil
end

-- Extract UUID from a comment line
function M.extract_uuid(line)
  return line:match(M.constants.uuid_pattern)
end

-- Check if a comment is opted out from tracking
function M.is_optout_comment(line)
  return line:match(M.constants.optout_pattern) ~= nil
end

-- Get all UUID markers from the task cache
function M.get_uuids_for_file(file_path)
  local uuids = {}

  for uuid, location in pairs(M.state.task_cache) do
    if location.file == file_path then
      table.insert(uuids, uuid)
    end
  end

  return uuids
end

-- Update tag status in cache
function M.update_task_status(uuid, status)
  if M.state.task_cache[uuid] then
    M.state.task_cache[uuid].status = status
    return true
  end
  return false
end

-- Get lines from a buffer with error handling
function M.get_buffer_lines(bufnr, start_line, end_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  -- Ensure valid line range
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  start_line = math.max(0, start_line)
  end_line = math.min(line_count, end_line or line_count)

  -- Get lines safely
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line, end_line, false)
  if not ok then
    return {}
  end

  return lines
end

return M

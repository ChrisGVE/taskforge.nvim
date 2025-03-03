-- lua/taskforge/buffer_utils.lua
-- Buffer utilities for preventing stack overflows

local M = {}

-- Cache of buffers currently being processed
M._processing_buffers = {}

-- Set a buffer processing lock to prevent recursion
-- @param bufnr number Buffer number
-- @param lock boolean Whether to lock or unlock
-- @return boolean Whether the operation was successful
function M.set_processing_lock(bufnr, lock)
  if lock then
    -- Check if already locked
    if M._processing_buffers[bufnr] then
      return false -- Already being processed
    end

    -- Set lock
    M._processing_buffers[bufnr] = true
    return true
  else
    -- Release lock
    M._processing_buffers[bufnr] = nil
    return true
  end
end

-- Check if a buffer is being processed
-- @param bufnr number Buffer number
-- @return boolean Whether the buffer is being processed
function M.is_buffer_processing(bufnr)
  return M._processing_buffers[bufnr] == true
end

-- Reset all buffer processing locks
-- Useful for recovering from a bad state
function M.reset_all_locks()
  M._processing_buffers = {}
end

-- Process a buffer safely with recursion protection
-- @param bufnr number Buffer number
-- @param callback function Function to process the buffer
-- @return boolean,any Success and result
function M.process_safely(bufnr, callback)
  -- Validate input
  if not bufnr or not callback then
    return false, "Invalid arguments"
  end

  -- Check if buffer is already being processed
  if M.is_buffer_processing(bufnr) then
    return false, "Buffer already being processed"
  end

  -- Set processing lock
  M.set_processing_lock(bufnr, true)

  -- Call the callback function with protection
  local success, result = pcall(callback)

  -- Release lock
  M.set_processing_lock(bufnr, false)

  -- Return result
  return success, result
end

-- Process multiple buffers safely
-- @param buffers table Array of buffer numbers
-- @param callback function Function to process each buffer
-- @return table Results for each buffer
function M.process_buffers(buffers, callback)
  local results = {}

  for _, bufnr in ipairs(buffers) do
    results[bufnr] = M.process_safely(bufnr, function()
      return callback(bufnr)
    end)
  end

  return results
end

-- Reset emergency command
function M.setup()
  vim.api.nvim_create_user_command("TaskforgeResetBuffers", function()
    M.reset_all_locks()
    vim.notify("Reset all Taskforge buffer locks", vim.log.levels.INFO)
  end, {
    desc = "Reset all Taskforge buffer processing locks",
  })
end

return M

-- lua/taskforge/tracker/init.lua
-- Tracker module entry point

local M = {}

-- Module state
M.state = {
  initialized = false,
  processed_buffers = {},
  edit_active = false,
}

-- Setup the tracker module and all submodules
function M.setup()
  -- Don't initialize twice
  if M.state.initialized then
    return M
  end

  -- Initialize required submodules
  local core = require("taskforge.tracker.core")
  local buffer = require("taskforge.tracker.buffer")
  local formatter = require("taskforge.tracker.formatter")

  -- Set up the submodules
  core.setup()
  buffer.setup()
  formatter.setup()

  -- Register commands
  M._register_commands()

  -- Set up event listeners and autocommands
  M._setup_events()

  -- Mark as initialized
  M.state.initialized = true

  return M
end

-- Register taskforge tag commands
function M._register_commands()
  vim.api.nvim_create_user_command("TaskforgeTag", function(opts)
    -- Ensure modules are loaded
    local tags = require("taskforge.tracker.tags")

    -- Handle command
    local subcmd = opts.fargs[1]
    if subcmd == "add" then
      tags.add_at_cursor()
    elseif subcmd == "remove" then
      tags.remove_at_cursor()
    elseif subcmd == "link" then
      tags.link_to_task()
    elseif subcmd == "optout" then
      tags.add_optout_at_cursor()
    elseif subcmd == "process" then
      -- Force reprocessing of current buffer
      local bufnr = vim.api.nvim_get_current_buf()
      local buffer = require("taskforge.tracker.buffer")
      M.state.processed_buffers[bufnr] = nil
      buffer.process(bufnr, true) -- true = initial processing mode
    end
  end, {
    nargs = 1,
    complete = function()
      return { "add", "remove", "link", "optout", "process" }
    end,
  })
end

-- Set up events and autocommands
function M._setup_events()
  -- Buffer enter events
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    callback = function(evt)
      local buffer = require("taskforge.tracker.buffer")
      local bufnr = evt.buf

      -- Skip if we've already processed this buffer
      if not M.state.processed_buffers[bufnr] then
        M.state.processed_buffers[bufnr] = true
        buffer.process(bufnr, true) -- true = initial processing mode
      end
    end,
  })

  -- Text change events
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    callback = function(evt)
      local core = require("taskforge.tracker.core")

      -- Mark that editing is active
      M.state.edit_active = true

      -- Reset debounce timer
      core.reset_debounce_timer(evt.buf)
    end,
  })

  -- Events for when editing ends
  vim.api.nvim_create_autocmd({ "InsertLeave", "TextChangedP" }, {
    callback = function(evt)
      local core = require("taskforge.tracker.core")

      -- Mark that editing has ended
      M.state.edit_active = false

      -- Process buffer after editing stops
      core.reset_debounce_timer(evt.buf)
    end,
  })

  -- Listen for buffer delete events to clean up state
  vim.api.nvim_create_autocmd({ "BufDelete" }, {
    callback = function(evt)
      -- Remove from processed buffers if it exists
      M.state.processed_buffers[evt.buf] = nil

      -- Clean up any other resources
      local core = require("taskforge.tracker.core")
      core.cleanup_buffer(evt.buf)
    end,
  })
end

-- Public API --

-- Process a buffer for task tags
function M.process_buffer(bufnr, initial)
  local buffer = require("taskforge.tracker.buffer")
  return buffer.process(bufnr, initial)
end

-- Process all task tags in the current buffer
function M.process_all()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Reset processed state
  M.state.processed_buffers[bufnr] = nil

  -- Process with initial flag
  local buffer = require("taskforge.tracker.buffer")
  return buffer.process(bufnr, true)
end

-- Add a tag at the current cursor position
function M.add_tag_at_cursor()
  local tags = require("taskforge.tracker.tags")
  return tags.add_at_cursor()
end

-- Remove a tag at the current cursor position
function M.remove_tag_at_cursor()
  local tags = require("taskforge.tracker.tags")
  return tags.remove_at_cursor()
end

-- Link the current comment to an existing task
function M.link_tag_to_task()
  local tags = require("taskforge.tracker.tags")
  return tags.link_to_task()
end

-- Add an opt-out marker to the current comment
function M.add_optout_at_cursor()
  local tags = require("taskforge.tracker.tags")
  return tags.add_optout_at_cursor()
end

-- Handle task status change
function M.handle_task_status_change(uuid, new_status)
  local tags = require("taskforge.tracker.tags")
  return tags.handle_task_status_change(uuid, new_status)
end

return M

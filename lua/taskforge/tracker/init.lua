-- lua/taskforge/tracker/init.lua
-- Tracker module entry point

local M = {}
local module_loader = nil

-- Module state
M.state = {
  initialized = false,
  processed_buffers = {},
  edit_active = false,
}

-- Initialize module_loader - do this lazily to avoid circular dependencies
local function get_module_loader()
  if not module_loader then
    module_loader = require("taskforge.module")
  end
  return module_loader
end

-- Setup the tracker module and all submodules
function M.setup()
  -- Don't initialize twice
  if M.state.initialized then
    return M
  end

  -- Initialize required submodules with safe loading
  local loader = get_module_loader()
  local core = loader.require("taskforge.tracker.core")
  local buffer = loader.require("taskforge.tracker.buffer")
  local formatter = loader.require("taskforge.tracker.formatter")

  -- Set up the submodules if they have setup functions
  if core.setup then
    pcall(core.setup)
  end
  if buffer.setup then
    pcall(buffer.setup)
  end
  if formatter.setup then
    pcall(formatter.setup)
  end

  -- Set up event listeners and autocommands
  M._setup_events()

  -- Expose the manual scan command
  vim.api.nvim_create_user_command("TaskforgeTagProcess", function()
    M.process_all(true) -- true = force scan
  end, {
    desc = "Process all untracked tags in the current buffer",
  })

  -- Register commands
  M._register_commands()

  -- Mark as initialized
  M.state.initialized = true

  return M
end

-- Register taskforge tag commands
function M._register_commands()
  vim.api.nvim_create_user_command("TaskforgeTag", function(opts)
    local loader = get_module_loader()

    -- Ensure modules are loaded
    local tags = loader.require("taskforge.tracker.tags")

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
      local buffer = loader.require("taskforge.tracker.buffer")
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
  local loader = get_module_loader()

  -- Buffer enter events
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    callback = function(evt)
      local buffer = loader.require("taskforge.tracker.buffer")
      local bufnr = evt.buf

      -- Skip if we've already processed this buffer
      if not M.state.processed_buffers[bufnr] then
        M.state.processed_buffers[bufnr] = true

        -- Use pcall to avoid errors during buffer processing
        pcall(function()
          buffer.process(bufnr, true) -- true = initial processing mode
        end)
      end
    end,
  })

  -- Text change events
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    callback = function(evt)
      local core = loader.require("taskforge.tracker.core")

      -- Mark that editing is active
      M.state.edit_active = true

      -- Reset debounce timer
      if core.reset_debounce_timer then
        core.reset_debounce_timer(evt.buf)
      end
    end,
  })

  -- Events for when editing ends
  vim.api.nvim_create_autocmd({ "InsertLeave", "TextChangedP" }, {
    callback = function(evt)
      local core = loader.require("taskforge.tracker.core")

      -- Mark that editing has ended
      M.state.edit_active = false

      -- Process buffer after editing stops
      if core.reset_debounce_timer then
        core.reset_debounce_timer(evt.buf)
      end
    end,
  })

  -- Listen for buffer delete events to clean up state
  vim.api.nvim_create_autocmd({ "BufDelete" }, {
    callback = function(evt)
      local core = loader.require("taskforge.tracker.core")

      -- Remove from processed buffers if it exists
      M.state.processed_buffers[evt.buf] = nil

      -- Clean up any other resources
      if core.cleanup_buffer then
        core.cleanup_buffer(evt.buf)
      end
    end,
  })
end

-- Public API --

-- Process a buffer for task tags
function M.process_buffer(bufnr, initial, force_scan)
  local loader = get_module_loader()
  local buffer = loader.require("taskforge.tracker.buffer")

  return buffer.process(bufnr, initial, force_scan)
end

-- Process batch tags with safely delayed UI loading
function M.process_batch(bufnr, candidates)
  -- Schedule UI loading to avoid circular dependencies
  vim.schedule(function()
    -- Use pcall to handle any errors that might occur
    pcall(function()
      local ui = require("taskforge.ui")
      if ui and ui.process_batch_tags then
        ui.process_batch_tags(bufnr, candidates)
      end
    end)
  end)
end

-- Process all task tags in the current buffer
function M.process_all(force_scan)
  local bufnr = vim.api.nvim_get_current_buf()
  local loader = get_module_loader()

  -- Reset processed state
  M.state.processed_buffers[bufnr] = nil

  -- Process with force_scan flag
  local buffer = loader.require("taskforge.tracker.buffer")
  return buffer.process(bufnr, true, force_scan) -- true = initial scan, force_scan for manual command
end

-- Add a tag at the current cursor position
function M.add_tag_at_cursor()
  local loader = get_module_loader()
  local tags = loader.require("taskforge.tracker.tags")
  return tags.add_at_cursor()
end

-- Remove a tag at the current cursor position
function M.remove_tag_at_cursor()
  local loader = get_module_loader()
  local tags = loader.require("taskforge.tracker.tags")
  return tags.remove_at_cursor()
end

-- Link the current comment to an existing task
function M.link_tag_to_task()
  local loader = get_module_loader()
  local tags = loader.require("taskforge.tracker.tags")
  return tags.link_to_task()
end

-- Add an opt-out marker to the current comment
function M.add_optout_at_cursor()
  local loader = get_module_loader()
  local tags = loader.require("taskforge.tracker.tags")
  return tags.add_optout_at_cursor()
end

-- Handle task status change
function M.handle_task_status_change(uuid, new_status)
  local loader = get_module_loader()
  local tags = loader.require("taskforge.tracker.tags")
  return tags.handle_task_status_change(uuid, new_status)
end

return M

-- lua/taskforge/integrations/trouble.lua
--
-- Integration with Trouble.nvim for displaying tracked comments

local M = {}

-- Register the Trouble provider
function M.setup()
  -- Safely require utils and debug
  local utils_ok, utils = pcall(require, "taskforge.utils")
  local debug_ok, debug = pcall(require, "taskforge.debug")

  local logger = function(msg, level)
    if debug_ok and debug.log then
      pcall(debug.log, "TROUBLE", msg)
    elseif utils_ok and utils.notify then
      pcall(utils.notify, "Trouble: " .. msg, level or vim.log.levels.INFO)
    end
  end

  -- Check if Trouble is available
  local has_trouble, trouble = pcall(require, "trouble")
  if not has_trouble then
    logger("Trouble.nvim is not available", vim.log.levels.INFO)
    return
  end

  -- Check for API compatibility
  if not trouble.providers then
    logger("Trouble.nvim API has changed, cannot register provider", vim.log.levels.WARN)
    return
  end

  -- Register our custom provider with safety checks
  pcall(function()
    trouble.providers["taskforge"] = {
      get = M.get_items,
      jump = M.jump_to_item,
    }
  end)

  -- Create command
  pcall(function()
    vim.api.nvim_create_user_command("TaskforgeTrouble", function(opts)
      -- Open trouble with our provider
      vim.cmd("Trouble taskforge")
    end, {
      desc = "Show tracked tasks in Trouble.nvim",
    })
  end)

  logger("Registered Taskforge provider for Trouble.nvim", vim.log.levels.INFO)
end

-- Get all tracked comments across files
-- @return table Items for Trouble.nvim
function M.get_items()
  local items = {}

  -- Safely get core state
  local core_ok, core = pcall(require, "taskforge.tracker.core")
  if not core_ok or not core.state or not core.state.task_cache then
    return {}
  end

  local tasks = core.state.task_cache or {}

  -- Convert to Trouble format
  for uuid, location in pairs(tasks) do
    local file_path = location.file
    local row = location.line - 1 -- 0-based line

    -- Skip if file doesn't exist or we can't access it
    if not file_path or vim.fn.filereadable(file_path) ~= 1 then
      goto continue
    end

    -- Try to get buffer
    local bufnr = vim.fn.bufadd(file_path)
    if not bufnr then
      goto continue
    end

    -- Make sure buffer is loaded
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      vim.fn.bufload(bufnr)
    end

    -- Get line content
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if row >= line_count then
      goto continue
    end

    local line_content = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

    -- Create item
    local item = {
      bufnr = bufnr,
      filename = file_path,
      lnum = location.line,
      col = 1, -- Default to first column
      text = line_content,
      type = "task", -- Custom type
      user_data = {
        uuid = uuid,
        description = location.description,
        status = location.status,
      },
    }

    -- Try to find the tag position for better column position
    local config_ok, config = pcall(require, "taskforge.config")
    if config_ok and config.get and config.get().tags and config.get().tags.definitions then
      for tag, _ in pairs(config.get().tags.definitions) do
        local tag_pos = line_content:find(tag)
        if tag_pos then
          item.col = tag_pos
          break
        end
      end
    end

    table.insert(items, item)
    ::continue::
  end

  return items
end

-- Jump to a specific item
-- @param item table Item from Trouble.nvim
function M.jump_to_item(item)
  -- Use our own jump function
  local tasks_ok, tasks = pcall(require, "taskforge.tasks")
  if tasks_ok and tasks.jump_to_task and item.user_data and item.user_data.uuid then
    tasks.jump_to_task(item.user_data.uuid)
    return true
  end

  -- Fallback to default Trouble behavior
  return false
end

return M

-- lua/taskforge/ui/init.lua
--
-- Main UI module for Taskforge

local M = {}
local utils = require("taskforge.utils")
local config = require("taskforge.config")

-- Initialize UI components
function M.setup()
  -- Load theme settings
  require("taskforge.ui.theme").setup()

  -- Register UI-related commands
  M._register_commands()

  -- Set up emergency exit command
  vim.api.nvim_create_user_command("TaskforgeUIClose", function()
    -- Close any open dialogs
    require("taskforge.ui.dialog").close_all()
    utils.notify("UI forcibly closed")
  end, {})

  return M
end

-- Register UI commands
function M._register_commands()
  -- Currently no UI-specific commands
  -- Will be implemented as needed
end

-- Process batch of tags
-- @param bufnr number Buffer number
-- @param candidates table Array of tag candidates
function M.process_batch_tags(bufnr, candidates)
  local batch = require("taskforge.ui.batch")
  batch.process_tags(bufnr, candidates)
end

-- Show tag review for buffer
-- @param bufnr number Buffer number
function M.review_tags_in_buffer(bufnr)
  local batch = require("taskforge.ui.batch")
  batch.review_tags_in_buffer(bufnr)
end

-- Show help dialog
-- @param content table|string Content to display
-- @param options table Dialog options
function M.show_help(content, options)
  local help = require("taskforge.ui.help")
  return help.show(content, options)
end

-- Show confirmation dialog
-- @param message string Message to display
-- @param callback function Callback function(result)
-- @param options table Dialog options
function M.confirm(message, callback, options)
  local dialog = require("taskforge.ui.dialog")
  return dialog.confirm(message, options, callback)
end

-- Show input dialog
-- @param prompt string Prompt message
-- @param callback function Callback function(result)
-- @param options table Dialog options
function M.input(prompt, callback, options)
  local dialog = require("taskforge.ui.dialog")
  return dialog.input(prompt, options, callback)
end

-- Show loading message in status line
-- @param message string Message to display
-- @return function Function to clear the message
function M.loading(message)
  local msg = message or "Loading..."
  local timer = vim.loop.new_timer()

  -- Setup spinner characters
  local spinners = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local i = 1

  -- Show initial message
  vim.api.nvim_echo({ { spinners[i] .. " " .. msg, "Normal" } }, false, {})

  -- Update spinner every 100ms
  timer:start(
    100,
    100,
    vim.schedule_wrap(function()
      i = (i % #spinners) + 1
      vim.api.nvim_echo({ { spinners[i] .. " " .. msg, "Normal" } }, false, {})
    end)
  )

  -- Return function to clear message
  return function()
    timer:stop()
    timer:close()
    vim.api.nvim_echo({ { "" } }, false, {})
  end
end

-- Show quick dialog
-- @param message string Message to display
-- @param options table Dialog options
-- @return table Dialog object
function M.notify_dialog(message, options)
  options = options or {}
  local timeout = options.timeout or 3000 -- 3 seconds default

  -- Create dialog
  local dialog = require("taskforge.ui.dialog")
  local d = dialog.create({
    title = options.title or "Notification",
    content = type(message) == "string" and vim.split(message, "\n") or message,
    width_percent = options.width_percent or 30,
    height_percent = options.height_percent or 20,
    position = "center",
    keymaps = {
      ["<Esc>"] = function(d)
        d:close()
      end,
      ["q"] = function(d)
        d:close()
      end,
      ["<Space>"] = function(d)
        d:close()
      end,
    },
  })

  -- Auto-close after timeout
  if timeout > 0 then
    vim.defer_fn(function()
      if d then
        d:close()
      end
    end, timeout)
  end

  return d
end

return M

-- lua/taskforge/ui/help.lua
--
-- Help dialog component for Taskforge UI

local M = {}
local utils = require("taskforge.utils")
local config = require("taskforge.config")
local ui_utils = require("taskforge.ui.utils")
local dialog = require("taskforge.ui.dialog")

-- Default help section titles
local section_titles = {
  navigation = "Navigation",
  actions = "Actions",
  edit = "Editing",
  view = "View Options",
  misc = "Miscellaneous",
}

-- Simple help dialog
-- @param content table|string Content to display
-- @param options table Dialog options
-- @return table Dialog object
function M.show(content, options)
  options = options or {}

  -- Format content if it's a string
  if type(content) == "string" then
    content = vim.split(content, "\n")
  end

  -- Set up basic options
  local opts = vim.tbl_extend("force", {
    id = "taskforge_help",
    title = options.title or "Help",
    mode = "help",
    content = content,

    -- Set up keymaps
    keymaps = {
      ["q"] = function(dialog)
        dialog:close()
      end,
      ["<Esc>"] = function(dialog)
        dialog:close()
      end,
      ["<CR>"] = function(dialog)
        dialog:close()
      end,
      ["<Space>"] = function(dialog)
        dialog:close()
      end,
    },

    -- Style options
    height_percent = 60,
    width_percent = 70,

    -- Set help dialog to read-only
    buf_options = {
      modifiable = false,
      readonly = true,
    },

    -- Don't position cursor
    enter = true,

    win_options = {
      cursorline = false,
      number = false,
      foldenable = false,
      scrolloff = 0,
    },

    -- Help windows typically don't need confirmation/cancellation
    on_close = options.on_close,
  }, options)

  -- Custom render function for help content with highlighting
  opts.render = function(self)
    if not self.popup or not self.popup.bufnr then
      return
    end

    local bufnr = self.popup.bufnr

    -- Make buffer modifiable temporarily
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

    -- Clear buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

    -- Add content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

    -- Apply highlighting
    vim.api.nvim_buf_clear_namespace(bufnr, self.namespace, 0, -1)

    -- Highlight section headers (lines ending with a colon)
    for i, line in ipairs(content) do
      if line:match("^[%w%s]+:$") or line:match("^[%w%s]+==+$") then
        vim.api.nvim_buf_add_highlight(bufnr, self.namespace, "Title", i - 1, 0, -1)
      elseif line:match("^%s*[–%-]%s") then
        -- Highlight bullet points
        local indent = line:match("^(%s*)"):len()
        vim.api.nvim_buf_add_highlight(bufnr, self.namespace, "Special", i - 1, indent, indent + 1)
      elseif line:match("^%s*•%s") then
        -- Highlight bullet points (Unicode)
        local indent = line:match("^(%s*)"):len()
        vim.api.nvim_buf_add_highlight(bufnr, self.namespace, "Special", i - 1, indent, indent + 1)
      end

      -- Highlight keys in single quotes, backticks, or brackets
      local text = line
      local start_pos = 0

      -- Find text between backticks
      for s, e in text:gmatch("()(`[^`]+`)()") do
        vim.api.nvim_buf_add_highlight(bufnr, self.namespace, "String", i - 1, start_pos + s - 1, start_pos + e - 1)
      end

      -- Find text between single quotes
      for s, e in text:gmatch("()('[^']+')()") do
        vim.api.nvim_buf_add_highlight(bufnr, self.namespace, "String", i - 1, start_pos + s - 1, start_pos + e - 1)
      end

      -- Find text in brackets
      for s, e in text:gmatch("()(<%w+>)()") do
        vim.api.nvim_buf_add_highlight(bufnr, self.namespace, "String", i - 1, start_pos + s - 1, start_pos + e - 1)
      end
    end

    -- Make buffer read-only again
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

    return self
  end

  -- Create and mount the dialog
  local help_dialog = dialog.create(opts)
  if help_dialog and opts.render then
    opts.render(help_dialog)
  end

  return help_dialog
end

-- Show help for a dialog
-- @param parent_dialog table Dialog to show help for
-- @return table Help dialog
function M.show_dialog_help(parent_dialog)
  -- Get keymaps configuration from original dialog
  local keymaps = parent_dialog.keymaps or {}
  local cfg = config.get()
  local cfg_keymaps = (cfg.interface and cfg.interface.keymaps) or {}

  -- Format keys for display
  local function format_key(key)
    if type(key) == "table" then
      return table.concat(key, ", ")
    elseif type(key) == "string" then
      -- Format special keys for display
      return key:gsub("<Esc>", "Esc"):gsub("<", "\\<"):gsub(">", "\\>")
    else
      return tostring(key)
    end
  end

  -- Build help content based on dialog type
  local content = {
    "Taskforge " .. (parent_dialog.title or "Dialog") .. " Help",
    string.rep("=", 40),
    "",
  }

  -- Add navigation section if applicable
  local navigation_keys = {}
  if keymaps.up or cfg.keymaps.up then
    table.insert(navigation_keys, format_key(keymaps.up or cfg.keymaps.up) .. "  : Move up")
  end

  if keymaps.down or cfg.keymaps.down then
    table.insert(navigation_keys, format_key(keymaps.down or cfg.keymaps.down) .. "  : Move down")
  end

  if #navigation_keys > 0 then
    table.insert(content, section_titles.navigation .. ":")
    for _, line in ipairs(navigation_keys) do
      table.insert(content, "  " .. line)
    end
    table.insert(content, "")
  end

  -- Add actions section
  local action_keys = {}
  if keymaps.confirm or cfg_keymaps.confirm then
    table.insert(action_keys, format_key(keymaps.confirm or cfg_keymaps.confirm) .. "  : Confirm/Apply")
  end

  if keymaps.cancel or cfg_keymaps.cancel then
    table.insert(action_keys, format_key(keymaps.cancel or cfg_keymaps.cancel) .. "  : Cancel/Exit")
  end

  if keymaps.select_task or cfg_keymaps.select_task then
    table.insert(action_keys, format_key(keymaps.select_task or cfg_keymaps.select_task) .. "  : Toggle selected item")
  end

  if keymaps.select_all_task or cfg_keymaps.select_all_task then
    table.insert(
      action_keys,
      format_key(keymaps.select_all_task or cfg_keymaps.select_all_task) .. "  : Toggle all items to match current"
    )
  end

  if #action_keys > 0 then
    table.insert(content, section_titles.actions .. ":")
    for _, line in ipairs(action_keys) do
      table.insert(content, "  " .. line)
    end
    table.insert(content, "")
  end

  -- Add edit section if applicable
  local edit_keys = {}
  if keymaps.edit or cfg_keymaps.edit then
    table.insert(edit_keys, format_key(keymaps.edit or cfg_keymaps.edit) .. "  : Edit item")
  end

  if keymaps.close_task or cfg_keymaps.close_task then
    table.insert(edit_keys, format_key(keymaps.close_task or cfg_keymaps.close_task) .. "  : Mark task as done")
  end

  if keymaps.delete_task or cfg_keymaps.delete_task then
    table.insert(edit_keys, format_key(keymaps.delete_task or cfg_keymaps.delete_task) .. "  : Delete task")
  end

  if #edit_keys > 0 then
    table.insert(content, section_titles.edit .. ":")
    for _, line in ipairs(edit_keys) do
      table.insert(content, "  " .. line)
    end
    table.insert(content, "")
  end

  -- Add general instructions
  table.insert(content, "")
  table.insert(content, "Press any key to close this help")

  -- Add custom help content if provided
  if parent_dialog.help_content then
    for _, line in ipairs(parent_dialog.help_content) do
      table.insert(content, line)
    end
  end

  return M.show(content, {
    title = parent_dialog.title .. " Help",
  })
end

-- Create help content for a specific dialog type
-- @param dialog_type string Dialog type
-- @return table Help content
function M.create_help_content(dialog_type)
  local content = {
    "Taskforge " .. dialog_type .. " Help",
    string.rep("=", 40),
    "",
  }

  -- Get configuration
  local cfg = config.get()
  local keymaps = (cfg.interface and cfg.interface.keymaps) or {}

  -- Add appropriate sections based on dialog type
  if dialog_type == "batch" or dialog_type == "tag_select" then
    -- Add navigation section
    table.insert(content, section_titles.navigation .. ":")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.up or { "k", "<Up>" }) .. "  : Move up")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.down or { "j", "<Down>" }) .. "  : Move down")
    table.insert(content, "")

    -- Add actions section
    table.insert(content, section_titles.actions .. ":")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.select_task or "v") .. "  : Toggle selected item")
    table.insert(
      content,
      "  " .. ui_utils.format_key(keymaps.select_all_task or "V") .. "  : Toggle all items to match current"
    )
    table.insert(content, "  " .. ui_utils.format_key(keymaps.quit or "q") .. "  : Apply selections and exit")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.unselect or "<esc>") .. "  : Cancel and exit")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.help or "?") .. "  : Show this help")
    table.insert(content, "")
  elseif dialog_type == "tag_review" or dialog_type == "task_list" then
    -- Add navigation section
    table.insert(content, section_titles.navigation .. ":")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.up or { "k", "<Up>" }) .. "  : Move up")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.down or { "j", "<Down>" }) .. "  : Move down")
    table.insert(content, "")

    -- Add actions section
    table.insert(content, section_titles.actions .. ":")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.select_task or "v") .. "  : Toggle selected item")
    table.insert(
      content,
      "  " .. ui_utils.format_key(keymaps.select_all_task or "V") .. "  : Toggle all items to match current"
    )
    table.insert(content, "  " .. ui_utils.format_key(keymaps.quit or "q") .. "  : Apply selections and exit")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.unselect or "<esc>") .. "  : Cancel and exit")
    table.insert(content, "")

    -- Add task management section
    table.insert(content, section_titles.edit .. ":")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.edit or "e") .. "  : Edit task")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.close_task or "d") .. "  : Mark task as done")
    table.insert(content, "  " .. ui_utils.format_key(keymaps.delete_task or "-") .. "  : Delete task")
    table.insert(content, "")
  end

  -- Add general instructions
  table.insert(content, "")
  table.insert(content, "Press any key to close this help")

  return content
end

return M

-- lua/taskforge/ui/utils.lua
--
-- Utility functions for UI components

local M = {}
local config = require("taskforge.config")

-- Calculate UI size based on configuration and window
-- @param options table Size options (width_percent, height_percent, min_width, etc.)
-- @param win_id number Window ID (default: current window)
-- @return table Size information (width, height, row, col)
function M.calculate_size(options, win_id)
  options = options or {}
  win_id = win_id or 0

  -- Get window dimensions
  local win_width = vim.api.nvim_win_get_width(win_id)
  local win_height = vim.api.nvim_win_get_height(win_id)

  -- Calculate dimensions based on percentages
  local width_percent = options.width_percent or 50
  local height_percent = options.height_percent or 50

  local width = math.floor(win_width * width_percent / 100)
  local height = math.floor(win_height * height_percent / 100)

  -- Apply minimum constraints
  width = math.max(width, options.min_width or 40)
  height = math.max(height, options.min_height or 10)

  -- Apply maximum constraints
  if options.max_width then
    width = math.min(width, options.max_width)
  end

  if options.max_height then
    height = math.min(height, options.max_height)
  end

  -- Ensure dialog fits within window with margins
  local margin = options.margin or 2
  width = math.min(width, win_width - (margin * 2))
  height = math.min(height, win_height - (margin * 2))

  -- Calculate position
  local position = options.position or "center"
  local row, col

  if position == "top" then
    row = math.floor(win_height * 0.15)
  elseif position == "center" then
    row = math.floor((win_height - height) / 2)
  elseif position == "bottom" then
    row = math.floor(win_height * 0.75) - math.floor(height / 2)
  elseif type(position) == "table" and position.row and position.col then
    -- Custom position
    row = position.row
    col = position.col
  else
    -- Default to center
    row = math.floor((win_height - height) / 2)
  end

  -- Calculate column if not explicitly set
  if not col then
    col = math.floor((win_width - width) / 2)
  end

  -- Ensure row and col are at least 0
  row = math.max(0, row)
  col = math.max(0, col)

  return {
    width = width,
    height = height,
    row = row,
    col = col,
  }
end

-- Format a key for display
-- @param key string|table Key or array of keys
-- @return string Formatted key string
function M.format_key(key)
  if type(key) == "table" then
    return table.concat(vim.tbl_map(M.format_key, key), ", ")
  elseif type(key) == "string" then
    -- Format special keys for display
    return key:gsub("<Esc>", "Esc"):gsub("<CR>", "Enter"):gsub("<Space>", "Space"):gsub("<(%w+)>", "\\<%1\\>")
  else
    return tostring(key)
  end
end

-- Try to load icon providers and get appropriate icons
-- @param icon_type string Type of icon to load
-- @param fallback string Fallback icon
-- @return string Icon
function M.get_icon(icon_type, fallback)
  local icon = fallback

  -- Try to load devicons
  local has_devicons, devicons = pcall(require, "nvim-web-devicons")
  if has_devicons then
    if icon_type == "checkmark" or icon_type == "selected" then
      local _, check_icon = devicons.get_icon("checkmark", "lua", { default = true })
      if check_icon then
        icon = check_icon
      end
    elseif icon_type == "close" or icon_type == "unselected" then
      local _, x_icon = devicons.get_icon("x", "lua", { default = true })
      if x_icon then
        icon = x_icon
      end
    else
      local _, custom_icon = devicons.get_icon(icon_type, "lua", { default = false })
      if custom_icon then
        icon = custom_icon
      end
    end
  else
    -- Try mini.icons as fallback
    local has_mini_icons, mini_icons = pcall(require, "mini.icons")
    if has_mini_icons then
      if icon_type == "checkmark" or icon_type == "selected" then
        icon = mini_icons.get("vim", "modified") or icon
      elseif icon_type == "close" or icon_type == "unselected" then
        icon = mini_icons.get("misc", "close") or icon
      else
        -- Try to get a relevant icon
        icon = mini_icons.get("misc", icon_type) or icon
      end
    end
  end

  return icon
end

-- Get common UI icons
-- @return table Icons table with standard icons
function M.get_ui_icons()
  -- Get config
  local cfg = config.get()
  local batch_ui = (cfg.interface and cfg.interface.batch_ui) or {}

  -- Default icons
  local icons = {
    selected = batch_ui.selected_glyph or "✓",
    unselected = batch_ui.unselected_glyph or "✗",
    folder = "",
    file = "",
    arrow_right = "→",
    arrow_down = "↓",
    tag = "#",
    project = "P",
    priority_high = "H",
    priority_medium = "M",
    priority_low = "L",
  }

  -- Try to improve icons using available icon providers
  icons.selected = M.get_icon("selected", icons.selected)
  icons.unselected = M.get_icon("unselected", icons.unselected)
  icons.folder = M.get_icon("folder", icons.folder)
  icons.file = M.get_icon("file", icons.file)

  return icons
end

-- Highlight a line in a buffer
-- @param bufnr number Buffer number
-- @param lnum number Line number (0-indexed)
-- @param hl_group string Highlight group
-- @param namespace number|nil Namespace ID (creates one if nil)
-- @return number Namespace ID used
function M.highlight_line(bufnr, lnum, hl_group, namespace)
  namespace = namespace or vim.api.nvim_create_namespace("taskforge_highlight")

  -- Clear existing highlights in this namespace for this line
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, lnum, lnum + 1)

  -- Add highlight
  vim.api.nvim_buf_add_highlight(bufnr, namespace, hl_group, lnum, 0, -1)

  return namespace
end

-- Center text for a width
-- @param text string Text to center
-- @param width number Width to center within
-- @param fill_char string Character to use for padding (default: space)
-- @return string Centered text
function M.center_text(text, width, fill_char)
  fill_char = fill_char or " "
  local text_width = vim.fn.strdisplaywidth(text)

  if text_width >= width then
    return text
  end

  local padding = width - text_width
  local left_pad = math.floor(padding / 2)

  return string.rep(fill_char, left_pad) .. text .. string.rep(fill_char, padding - left_pad)
end

-- Format a table row with fixed column widths
-- @param columns table Array of column values
-- @param widths table Array of column widths
-- @param separators table|nil Array of column separators (default: spaces)
-- @return string Formatted row
function M.format_row(columns, widths, separators)
  separators = separators or {}
  local parts = {}

  for i, col in ipairs(columns) do
    local width = widths[i] or 10
    local value = tostring(col or "")

    -- Clip text if longer than width
    if #value > width then
      value = value:sub(1, width - 3) .. "..."
    end

    -- Pad with spaces
    value = value .. string.rep(" ", width - vim.fn.strdisplaywidth(value))

    table.insert(parts, value)

    -- Add separator if not the last column
    if i < #columns and separators[i] then
      table.insert(parts, separators[i])
    elseif i < #columns then
      table.insert(parts, " ")
    end
  end

  return table.concat(parts, "")
end

-- Convert a keymap to a display string for help text
-- @param key string|table Key or keys
-- @param action string Description of the action
-- @param width number|nil Width for formatting (nil for no padding)
-- @return string Formatted keymap help text
function M.format_keymap_help(key, action, width)
  local key_str = M.format_key(key)

  if width then
    return string.format("%-" .. width .. "s: %s", key_str, action)
  else
    return key_str .. ": " .. action
  end
end

-- Create standard help content
-- @param mode string Dialog mode
-- @return table Help text lines
function M.create_help_content(mode)
  -- Get keymaps from config
  local cfg = config.get().interface or {}
  local keymaps = cfg.keymaps or {}

  -- Start with title
  local content = {
    "Taskforge " .. mode:gsub("^%l", string.upper) .. " Help",
    string.rep("=", 40),
    "",
  }

  -- Navigation section
  local nav_keys = {
    M.format_keymap_help(keymaps.up or { "k", "<Up>" }, "Move up", 12),
    M.format_keymap_help(keymaps.down or { "j", "<Down>" }, "Move down", 12),
  }

  if #nav_keys > 0 then
    table.insert(content, "Navigation:")
    for _, line in ipairs(nav_keys) do
      table.insert(content, "  " .. line)
    end
    table.insert(content, "")
  end

  -- Action section based on mode
  local action_keys = {}

  -- Common actions
  table.insert(action_keys, M.format_keymap_help(keymaps.quit or "q", "Apply and exit", 12))
  table.insert(action_keys, M.format_keymap_help(keymaps.unselect or "<Esc>", "Cancel and exit", 12))
  table.insert(action_keys, M.format_keymap_help(keymaps.help or "?", "Show this help", 12))

  -- Mode-specific actions
  if mode == "tag_select" or mode == "tag_review" or mode == "task_list" then
    table.insert(action_keys, 2, M.format_keymap_help(keymaps.select_task or "v", "Toggle selected item", 12))
    table.insert(action_keys, 3, M.format_keymap_help(keymaps.select_all_task or "V", "Toggle all items", 12))
  end

  if mode == "tag_review" or mode == "task_list" then
    table.insert(action_keys, 4, M.format_keymap_help(keymaps.edit or "e", "Edit task", 12))
    table.insert(action_keys, 5, M.format_keymap_help(keymaps.close_task or "d", "Mark as done", 12))
    table.insert(action_keys, 6, M.format_keymap_help(keymaps.delete_task or "-", "Delete task", 12))
  end

  if #action_keys > 0 then
    table.insert(content, "Actions:")
    for _, line in ipairs(action_keys) do
      table.insert(content, "  " .. line)
    end
    table.insert(content, "")
  end

  -- Add footer
  table.insert(content, "")
  table.insert(content, "Press any key to close this help")

  return content
end

return M

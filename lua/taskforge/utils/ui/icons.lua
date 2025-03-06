-- lua/taskforge/ui/icons.lua
--
-- Icon handling for Taskforge UI

local M = {}
local config = require("taskforge.config")
local utils = require("taskforge.utils")

-- Default icons (fallbacks when no icon provider available)
M.defaults = {
  -- Checkboxes
  selected = "✓",
  unselected = "✗",

  -- Priorities
  priority_high = "H",
  priority_medium = "M",
  priority_low = "L",

  -- Status
  status_pending = "●",
  status_completed = "✓",
  status_deleted = "✗",

  -- Files and folders
  folder = "📁",
  file = "📄",

  -- UI elements
  arrow_right = "→",
  arrow_down = "↓",
  arrow_up = "↑",
  arrow_left = "←",

  -- Tags and projects
  tag = "#",
  project = "P",

  -- Misc
  star = "★",
  warning = "⚠",
  error = "✘",
  info = "ℹ",
  help = "?",
  menu = "≡",
}

-- Check if devicons is available
function M.has_devicons()
  return pcall(require, "nvim-web-devicons")
end

-- Check if mini.icons is available
function M.has_mini_icons()
  return pcall(require, "mini.icons")
end

-- Get an icon by name
-- @param name string Icon name
-- @param default string|nil Default icon if not found
-- @return string Icon
function M.get(name, default)
  -- Check config first
  local cfg = config.get()
  local batch_ui = (cfg.interface and cfg.interface.batch_ui) or {}

  if name == "selected" and batch_ui.selected_glyph then
    return batch_ui.selected_glyph
  elseif name == "unselected" and batch_ui.unselected_glyph then
    return batch_ui.unselected_glyph
  end

  -- Try to get from devicons
  if M.has_devicons() then
    local devicons = require("nvim-web-devicons")

    -- Special handling for known icon types
    if name == "selected" or name == "checkmark" then
      local _, check_icon = devicons.get_icon("checkmark.lua", "lua", { default = false })
      if check_icon then
        return check_icon
      end
    elseif name == "unselected" or name == "close" then
      local _, x_icon = devicons.get_icon("x.lua", "lua", { default = false })
      if x_icon then
        return x_icon
      end
    elseif name == "folder" then
      local _, folder_icon = devicons.get_icon("folder", nil, { default = false })
      if folder_icon then
        return folder_icon
      end
    elseif name == "file" then
      local _, file_icon = devicons.get_icon("file", nil, { default = false })
      if file_icon then
        return file_icon
      end
    end
  end

  -- Try mini.icons as fallback
  if M.has_mini_icons() then
    local mini_icons = require("mini.icons")

    if name == "selected" or name == "checkmark" then
      local check = mini_icons.get("vim", "modified")
      if check then
        return check
      end
    elseif name == "unselected" or name == "close" then
      local close = mini_icons.get("misc", "close")
      if close then
        return close
      end
    elseif name == "folder" then
      local folder = mini_icons.get("misc", "folder")
      if folder then
        return folder
      end
    elseif name == "file" then
      local file = mini_icons.get("misc", "file")
      if file then
        return file
      end
    elseif name == "arrow_right" then
      local arrow = mini_icons.get("misc", "arrow_right")
      if arrow then
        return arrow
      end
    elseif name == "project" then
      local project = mini_icons.get("misc", "list")
      if project then
        return project
      end
    end
  end

  -- Return default or fallback
  return default or M.defaults[name] or "?"
end

-- Get icon set
-- @return table Icons table
function M.get_all()
  local icons = vim.deepcopy(M.defaults)

  -- Override with any detected icons
  for name, _ in pairs(icons) do
    icons[name] = M.get(name, icons[name])
  end

  return icons
end

-- Get fileytpe icon for a file
-- @param filename string Filename
-- @param extension string|nil File extension
-- @return string Icon for file
function M.get_file_icon(filename, extension)
  -- Try to get from devicons
  if M.has_devicons() then
    local devicons = require("nvim-web-devicons")
    local icon, _ = devicons.get_icon(filename, extension, { default = true })
    if icon then
      return icon
    end
  end

  -- Try mini.icons
  if M.has_mini_icons() then
    local mini_icons = require("mini.icons")
    local icon = mini_icons.get("misc", "file")
    if icon then
      return icon
    end
  end

  -- Fallback
  return M.defaults.file
end

-- Get an appropriate icon for task priority
-- @param priority string Priority value (H/M/L)
-- @return string Icon
function M.get_priority_icon(priority)
  if priority == "H" then
    return M.get("priority_high")
  elseif priority == "M" then
    return M.get("priority_medium")
  elseif priority == "L" then
    return M.get("priority_low")
  else
    return ""
  end
end

-- Get an appropriate icon for task status
-- @param status string Status value
-- @return string Icon
function M.get_status_icon(status)
  if status == "completed" or status == "done" then
    return M.get("status_completed")
  elseif status == "deleted" then
    return M.get("status_deleted")
  elseif status == "pending" then
    return M.get("status_pending")
  else
    return ""
  end
end

return M

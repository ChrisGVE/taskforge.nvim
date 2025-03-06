-- lua/taskforge/ui/theme.lua
--
-- Theme and styling for Taskforge UI components

local M = {}
local utils = require("taskforge.utils")
local config = require("taskforge.config")

-- Define default highlight groups
M.highlights = {
  -- Dialog elements
  DialogTitle = { link = "Title" },
  DialogBorder = { link = "FloatBorder" },
  DialogBackground = { link = "Normal" },
  DialogHeader = { link = "Special" },
  DialogFooter = { link = "Comment" },

  -- Item states
  ItemSelected = { link = "DiagnosticOk" },
  ItemUnselected = { link = "DiagnosticError" },
  ItemFocused = { link = "Visual" },
  ItemHighlight = { link = "Search" },

  -- Task elements
  TaskTag = { link = "Identifier" },
  TaskProject = { link = "Type" },
  TaskDescription = { link = "Normal" },
  TaskDue = { link = "Special" },
  TaskUrgent = { link = "ErrorMsg" },
  TaskNormal = { link = "Comment" },

  -- Priority
  PriorityHigh = { link = "ErrorMsg" },
  PriorityMedium = { link = "WarningMsg" },
  PriorityLow = { link = "Comment" },

  -- Status
  StatusPending = { link = "WarningMsg" },
  StatusCompleted = { link = "DiagnosticOk" },
  StatusDeleted = { link = "DiagnosticError" },

  -- Misc
  HelpKey = { link = "String" },
  HelpTitle = { link = "Title" },
  HelpCommand = { link = "Function" },
}

-- Setup highlights
function M.setup_highlights()
  for name, def in pairs(M.highlights) do
    if def.link then
      vim.api.nvim_set_hl(0, "Taskforge" .. name, { link = def.link })
    else
      vim.api.nvim_set_hl(0, "Taskforge" .. name, def)
    end
  end

  -- Apply custom highlight from config
  local cfg = config.get().highlights or {}

  -- Set up urgent highlight
  if cfg.urgent and cfg.urgent.group then
    vim.api.nvim_set_hl(0, "TaskforgeUrgent", { link = cfg.urgent.group })
  else
    local hl = M._get_default_hl_group("urgent")
    vim.api.nvim_set_hl(0, "TaskforgeUrgent", hl)
  end

  -- Set up normal highlight
  if cfg.normal and cfg.normal.group then
    vim.api.nvim_set_hl(0, "TaskforgeNormal", { link = cfg.normal.group })
  else
    local hl = M._get_default_hl_group("normal")
    vim.api.nvim_set_hl(0, "TaskforgeNormal", hl)
  end
end

-- Get default highlight for a type
-- @param which string The highlight type to get
-- @return table Highlight definition
function M._get_default_hl_group(which)
  if which == "urgent" then
    local hl = vim.api.nvim_get_hl(0, { name = "@keyword" })
    return {
      bg = hl.bg,
      fg = hl.fg,
      cterm = hl.cterm,
      bold = hl.bold,
      italic = hl.italic,
      reverse = hl.reverse,
    }
  elseif which == "normal" then
    local hl = vim.api.nvim_get_hl(0, { name = "Comment" })
    return {
      bg = hl.bg,
      fg = hl.fg,
      cterm = hl.cterm,
      bold = hl.bold,
      italic = hl.italic,
      reverse = hl.reverse,
    }
  else
    return {
      italic = true,
    }
  end
end

-- Setup theme
function M.setup()
  -- Create highlights
  M.setup_highlights()

  -- Setup highlight autocmd to maintain highlights on colorscheme change
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      M.setup_highlights()
    end,
  })
end

-- Get colors for priorities
function M.get_priority_colors()
  return {
    H = "TaskforgePriorityHigh",
    M = "TaskforgePriorityMedium",
    L = "TaskforgePriorityLow",
  }
end

-- Get colors for statuses
function M.get_status_colors()
  return {
    pending = "TaskforgeStatusPending",
    completed = "TaskforgeStatusCompleted",
    done = "TaskforgeStatusCompleted",
    deleted = "TaskforgeStatusDeleted",
  }
end

-- Highlight a task item based on its properties
-- @param bufnr number Buffer number
-- @param line number Line number (0-indexed)
-- @param item table Task item
-- @param namespace number|nil Namespace ID
-- Highlight a task item based on its properties
-- @param bufnr number Buffer number
-- @param line number Line number (0-indexed)
-- @param item table Task item
-- @param namespace number|nil Namespace ID
function M.highlight_task_item(bufnr, line, item, namespace)
  namespace = namespace or vim.api.nvim_create_namespace("taskforge_theme")

  -- Get line text
  local line_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""

  -- Highlight by components
  local offset = 0

  -- Highlight checkbox if present
  local check_start = line_text:find("%[")
  if check_start then
    local check_end = line_text:find("]", check_start)
    if check_end then
      local highlight = item.selected and "TaskforgeItemSelected" or "TaskforgeItemUnselected"
      vim.api.nvim_buf_add_highlight(bufnr, namespace, highlight, line, check_start - 1, check_end)
      offset = check_end + 1
    end
  end

  -- Highlight tag if present
  local tag_start = line_text:find("[A-Z]+:", offset)
  if tag_start then
    local tag_end = line_text:find(":", tag_start)
    if tag_end then
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "TaskforgeTaskTag", line, tag_start - 1, tag_end)
      offset = tag_end + 1
    end
  end

  -- Highlight priority if present
  if item.priority then
    local priority_color = M.get_priority_colors()[item.priority] or "Normal"
    local priority_pos = line_text:find(item.priority, offset)
    if priority_pos then
      vim.api.nvim_buf_add_highlight(
        bufnr,
        namespace,
        priority_color,
        line,
        priority_pos - 1,
        priority_pos - 1 + #item.priority
      )
    end
  end

  -- Highlight status if present
  if item.status then
    local status_color = M.get_status_colors()[item.status] or "Normal"
    local status_pos = line_text:find(item.status, offset)
    if status_pos then
      vim.api.nvim_buf_add_highlight(
        bufnr,
        namespace,
        status_color,
        line,
        status_pos - 1,
        status_pos - 1 + #item.status
      )
    end
  end

  -- Highlight project if present
  if item.project then
    local project_pos = line_text:find(item.project, offset)
    if project_pos then
      vim.api.nvim_buf_add_highlight(
        bufnr,
        namespace,
        "TaskforgeTaskProject",
        line,
        project_pos - 1,
        project_pos - 1 + #item.project
      )
    end
  end

  -- Highlight by urgency
  if item.urgency then
    local cfg = config.get()
    local threshold = (cfg.highlights and cfg.highlights.urgent and cfg.highlights.urgent.threshold) or 8.0

    if tonumber(item.urgency) >= threshold then
      -- No need to add another highlight if we already highlighted components
      if not (check_start or tag_start) then
        vim.api.nvim_buf_add_highlight(bufnr, namespace, "TaskforgeUrgent", line, 0, -1)
      end
    end
  end

  return namespace
end

return M

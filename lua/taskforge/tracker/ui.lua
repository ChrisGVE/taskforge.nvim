-- lua/taskforge/tracker/ui.lua
--
-- UI components for tag interaction including reusable batch processing dialog

local M = {}
local utils = require("taskforge.utils")
local core = require("taskforge.tracker.core")
local config = require("taskforge.config")
local debug = require("taskforge.debug")

-- Namespace for batch tag processing
-- This is a state store specific to this module
local batch = {
  active = false,
  data_items = {},
  selected_index = 1,
  visible = false,
  source_bufnr = nil,
  highlight_namespace = nil,
  namespace = nil,
  mode = "tag_select", -- Mode: "tag_select", "tag_review", "task_list"
  columns = {}, -- Column specifications
  actions = {}, -- Action callbacks
  formatter = nil, -- Custom formatter function
  on_complete = nil, -- Callback when completed
}

-- Cached UI components
local ui_components = {
  popup = nil,
  menu = nil,
}

-- Try to load icon providers
local function get_icons()
  local icons = {
    selected = "✓",
    unselected = "✗",
  }

  -- Try to load configuration
  local cfg = config.get().interface and config.get().interface.batch_ui or {}

  -- Use configured glyphs if available
  if cfg.selected_glyph then
    icons.selected = cfg.selected_glyph
  end

  if cfg.unselected_glyph then
    icons.unselected = cfg.unselected_glyph
  end

  -- Try to use nvim-web-devicons if enabled and available
  if cfg.use_devicons ~= false then
    local has_devicons, devicons = pcall(require, "nvim-web-devicons")
    if has_devicons then
      -- Get a checkmark-like icon from devicons if possible
      local _, icon = devicons.get_icon("checkmark", "lua", { default = true })
      if icon then
        icons.selected = icon
      end

      -- Get an x-like icon from devicons if possible
      local _, x_icon = devicons.get_icon("x", "lua", { default = true })
      if x_icon then
        icons.unselected = x_icon
      end
    else
      -- Try mini.icons as fallback
      local has_mini_icons, mini_icons = pcall(require, "mini.icons")
      if has_mini_icons then
        icons.selected = mini_icons.get("vim", "modified") or icons.selected
        icons.unselected = mini_icons.get("misc", "close") or icons.unselected
      end
    end
  end

  return icons
end

-- Calculate UI size based on configuration and window
local function calculate_ui_size(mode)
  local cfg = config.get().interface and config.get().interface.batch_ui or {}

  -- Get current window dimensions
  local win_width = vim.api.nvim_win_get_width(0)
  local win_height = vim.api.nvim_win_get_height(0)

  -- Calculate dimensions based on percentages with mode-specific adjustments
  local width_percent = cfg.width_percent or (mode == "task_list" and 90 or 80)
  local height_percent = cfg.height_percent or (mode == "task_list" and 50 or 20)

  -- Calculate dimensions with constraints
  local width = math.floor(win_width * width_percent / 100)
  local height = math.floor(win_height * height_percent / 100)

  -- Apply minimum constraints
  width = math.max(width, cfg.min_width or 50)
  height = math.max(height, cfg.min_height or 5)

  -- Apply maximum constraints
  if cfg.max_width then
    width = math.min(width, cfg.max_width)
  end

  if cfg.max_height then
    height = math.min(height, cfg.max_height)
  end

  -- Ensure dialog fits within window
  width = math.min(width, win_width - 4)
  height = math.min(height, win_height - 4)

  -- Calculate position
  local position = cfg.position or "top"
  local row

  if position == "top" then
    row = math.floor(win_height * 0.15)
  elseif position == "center" then
    row = math.floor(win_height / 2) - math.floor(height / 2)
  elseif position == "bottom" then
    row = math.floor(win_height * 0.75) - math.floor(height / 2)
  else
    row = math.floor(win_height * 0.15)
  end

  local col = math.floor((win_width - width) / 2)

  -- Ensure row is at least 1
  row = math.max(1, row)

  return {
    width = width,
    height = height,
    row = row,
    col = col,
  }
end

-- Process batch tag candidates
-- This is the entry point for the UI processing
function M.batch_process_tags(bufnr, candidates)
  utils.notify("Processing " .. #candidates .. " tag candidates", vim.log.levels.INFO)

  -- Group and process candidates by type
  local buffer = require("taskforge.tracker.buffer")
  local result = buffer.process_candidates_by_type(bufnr, candidates)

  -- If we processed some tags automatically, show a notification
  local auto_msg = ""
  if result.auto_processed > 0 then
    auto_msg = string.format("%d tags processed automatically. ", result.auto_processed)
  end

  -- If there are interactive tags to handle, show the UI
  if #result.interactive > 0 then
    utils.notify(
      auto_msg .. string.format("Found %d tags requiring user decision", #result.interactive),
      vim.log.levels.INFO
    )
    M.show_batch_dialog({
      source_bufnr = bufnr,
      data_items = result.interactive,
      mode = "tag_select",
      title = "Select Tags to Create",
      columns = { "select", "tag", "description", "line" },
      item_formatter = function(item, idx)
        return {
          select = item.selected,
          tag = item.tag,
          description = item.description,
          line = "line " .. (item.lnum + 1),
          _data = item, -- Store full item data for callbacks
        }
      end,
      key_select = function(item)
        item.selected = not item.selected
        return true -- Return true to refresh display
      end,
      on_complete = function(items, cancelled)
        if not cancelled then
          M.apply_tag_selections(bufnr, items)
        end
      end,
    })
  elseif result.auto_processed > 0 or result.manual_processed > 0 then
    utils.notify(auto_msg .. string.format("%d tags notified for manual handling", result.manual_processed))
  else
    utils.notify("No tags found to process")
  end
end

-- Apply tag selections after batch processing
function M.apply_tag_selections(bufnr, items)
  -- Process selected tags
  local processed = 0
  local optout = 0
  local buffer = require("taskforge.tracker.buffer")
  local tags = require("taskforge.tracker.tags")

  for _, item in ipairs(items) do
    if item.selected then
      -- Create task
      buffer.process_auto_tag(bufnr, item._data)
      processed = processed + 1
    else
      -- Add opt-out marker
      tags.add_optout_marker(bufnr, item._data.lnum)
      optout = optout + 1
    end
  end

  -- Notify results
  if processed > 0 or optout > 0 then
    local msg = string.format("Processed %d tags, marked %d tags as [notrack]", processed, optout)
    utils.notify(msg)
  end
end

-- Create help popup
function M.show_help_popup(help_config)
  local has_nui, Popup = pcall(require, "nui.popup")
  if not has_nui then
    utils.notify("Help requires nui.nvim", vim.log.levels.WARN)
    return
  end

  -- Get keymaps configuration
  local cfg = config.get().interface or {}
  local keymaps = cfg.keymaps or {}

  -- Format keys for display
  local format_keymap = function(key)
    if type(key) == "table" then
      return table.concat(key, ", ")
    else
      return key
    end
  end

  -- Default content
  local help_text = {
    "Taskforge Dialog Help",
    "==========================",
    "",
    "Navigation:",
    "  " .. format_keymap(keymaps.up or { "k", "<Up>" }) .. "  : Move up",
    "  " .. format_keymap(keymaps.down or { "j", "<Down>" }) .. "  : Move down",
    "",
    "Actions:",
    "  " .. format_keymap(keymaps.select_task or "v") .. "  : Toggle selected item",
    "  " .. format_keymap(keymaps.select_all_task or "V") .. "  : Toggle all items to match current",
    "  " .. format_keymap(keymaps.quit or "q") .. "  : Apply selections and exit",
    "  " .. format_keymap(keymaps.unselect or "<esc>") .. "  : Cancel and exit",
    "  " .. format_keymap(keymaps.help or "?") .. "  : Show this help",
    "",
    "Press any key to close",
  }

  -- Override with custom help if provided
  if help_config and help_config.help_text then
    help_text = help_config.help_text
  end

  -- Create popup
  local popup = Popup({
    enter = false, -- No cursor in help window
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Help ",
        top_align = "center",
      },
    },
    position = "50%",
    size = {
      width = 60,
      height = #help_text + 2,
    },
    win_options = {
      cursorline = false,
      number = false,
      foldenable = false,
      scrolloff = 0,
    },
  })

  -- Mount the popup
  popup:mount()

  -- Set content
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, help_text)

  -- Set buffer options
  vim.bo[popup.bufnr].modifiable = false
  vim.bo[popup.bufnr].readonly = true

  -- Add highlighting
  vim.api.nvim_buf_add_highlight(popup.bufnr, -1, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(popup.bufnr, -1, "Comment", 1, 0, -1)
  vim.api.nvim_buf_add_highlight(popup.bufnr, -1, "String", 3, 0, -1)
  vim.api.nvim_buf_add_highlight(popup.bufnr, -1, "String", 7, 0, -1)

  -- Close on *ANY* key - map all printable ASCII characters
  local all_keys = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890`~!@#$%^&*()-_=+[{]}\\|;:'\",<.>/? "
  for i = 1, #all_keys do
    local c = all_keys:sub(i, i)
    popup:map("n", c, function()
      popup:unmount()
    end, { noremap = true })
  end

  -- Also close on common special keys
  local special_keys = { "<CR>", "<Space>", "<Esc>", "<Tab>", "<BS>", "<Up>", "<Down>", "<Left>", "<Right>" }
  for _, key in ipairs(special_keys) do
    popup:map("n", key, function()
      popup:unmount()
    end, { noremap = true })
  end

  -- Make sure it's closed when window loses focus
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    buffer = popup.bufnr,
    callback = function()
      popup:unmount()
    end,
    once = true,
  })

  return popup
end

-- Show batch UI in a more generalized way
-- @param options table Dialog configuration options
--   - source_bufnr: Source buffer number
--   - data_items: Array of data items
--   - mode: Dialog mode ("tag_select", "tag_review", "task_list")
--   - title: Dialog title
--   - columns: Array of column names to display
--   - item_formatter: Function to format items (item, idx) -> table of column values
--   - key_select: Function to handle toggle select (item) -> boolean refresh?
--   - on_complete: Function called when dialog is complete (items, cancelled)
function M.show_batch_dialog(options)
  -- Ensure we have NUI
  local has_nui, NuiPopup = pcall(require, "nui.popup")
  if not has_nui then
    utils.notify("Batch UI requires nui.nvim", vim.log.levels.WARN)
    -- Fall back to simple selection
    M.show_simple_selection(options)
    return
  end

  -- Set up internal batch state
  batch.active = true
  batch.data_items = options.data_items or {}
  batch.source_bufnr = options.source_bufnr
  batch.mode = options.mode or "tag_select"
  batch.columns = options.columns or { "select", "tag", "description", "line" }
  batch.formatter = options.item_formatter
  batch.on_complete = options.on_complete
  batch.actions = {
    key_select = options.key_select,
    key_select_all = options.key_select_all,
    key_action = options.key_action,
    key_edit = options.key_edit,
    key_done = options.key_done,
    key_delete = options.key_delete,
  }

  -- Get configuration
  local cfg = config.get().interface or {}
  local keymaps = cfg.keymaps or {}

  -- Extract actual keys from config with defaults
  local key_up = keymaps.up or "k"
  if type(key_up) == "table" then
    key_up = key_up[1]
  end

  local key_down = keymaps.down or "j"
  if type(key_down) == "table" then
    key_down = key_down[1]
  end

  local key_select = keymaps.select_task or "v"
  local key_select_all = keymaps.select_all_task or "V"
  local key_quit = keymaps.quit or "q"
  local key_cancel = keymaps.unselect or "<Esc>"
  local key_help = keymaps.help or "?"
  local key_action = keymaps.action or "a"

  -- Additional keys for task review/management
  local key_edit = keymaps.edit or "e"
  local key_done = keymaps.close_task or "d"
  local key_delete = keymaps.delete_task or "-"

  -- Format keys for display (handle special keys)
  local display_quit = key_quit:gsub("<", "\\<")
  local display_cancel = key_cancel:gsub("<Esc>", "Esc"):gsub("<", "\\<")
  local display_help = key_help:gsub("<", "\\<")

  -- Calculate size based on mode
  local size = calculate_ui_size(batch.mode)

  -- Prepare footer text based on mode
  local footer_text = string.format(" %s: Apply | %s: Cancel | %s: Help ", display_quit, display_cancel, display_help)

  if batch.mode == "task_list" or batch.mode == "tag_review" then
    footer_text = string.format(
      " %s: Apply | %s: Edit | %s: Done | %s: Delete | %s: Help ",
      display_quit,
      keymaps.edit or "e",
      keymaps.close_task or "d",
      keymaps.delete_task or "-",
      display_help
    )
  end

  -- Create popup with dynamic key display
  local popup = NuiPopup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " " .. (options.title or "Taskforge") .. " ",
        top_align = "center",
        bottom = footer_text,
        bottom_align = "center",
      },
    },
    position = {
      row = size.row,
      col = size.col,
    },
    size = {
      width = size.width,
      height = size.height,
    },
    win_options = {
      cursorline = true, -- Highlight current line
      winhighlight = "Normal:Normal,CursorLine:Visual", -- Highlight current line with Visual
    },
  })

  -- Store popup in module state
  ui_components.popup = popup

  -- Mount the popup
  popup:mount()

  -- Create namespace for highlights that need to persist
  batch.namespace = vim.api.nvim_create_namespace("taskforge_ui_highlights")

  -- Render content
  M.render_batch_dialog()

  -- Force cursor to first item row and focus window
  vim.defer_fn(function()
    if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      vim.api.nvim_set_current_win(popup.winid)
      vim.api.nvim_win_set_cursor(popup.winid, { 3, 0 })

      -- Jump to first item in source
      if #batch.data_items > 0 and batch.source_bufnr then
        M.highlight_item_source(0)
      end
    end
  end, 10)

  -- Setup keymaps
  local opts = { noremap = true, silent = true }

  -- Use configured keys for movement
  local up_keys = type(keymaps.up) == "table" and keymaps.up or { keymaps.up or "k", "<Up>" }
  local down_keys = type(keymaps.down) == "table" and keymaps.down or { keymaps.down or "j", "<Down>" }

  -- Movement: up
  for _, key in ipairs(type(up_keys) == "table" and up_keys or { up_keys }) do
    popup:map("n", key, function()
      local cursor = vim.api.nvim_win_get_cursor(popup.winid)
      local row = cursor[1]
      -- Don't go above the first item
      if row > 3 then
        vim.api.nvim_win_set_cursor(popup.winid, { row - 1, 0 })
        M.highlight_item_source(row - 3 - 1) -- after moving up
      end
    end, opts)
  end

  -- Movement: down
  for _, key in ipairs(type(down_keys) == "table" and down_keys or { down_keys }) do
    popup:map("n", key, function()
      local cursor = vim.api.nvim_win_get_cursor(popup.winid)
      local row = cursor[1]
      -- Don't go past the last item or above first item
      local content_len = #batch.data_items + 2 -- +2 for header rows
      if row < content_len + 1 then
        vim.api.nvim_win_set_cursor(popup.winid, { row + 1, 0 })
        M.highlight_item_source(row - 3 + 1) -- after moving down
      end
    end, opts)
  end

  -- Toggle item: use select_task key
  popup:map("n", key_select, function()
    local cursor = vim.api.nvim_win_get_cursor(popup.winid)
    local row = cursor[1]

    -- Only toggle item rows, not headers
    if row >= 3 and row - 3 < #batch.data_items then
      local item_idx = row - 3
      local item = batch.data_items[item_idx + 1]

      -- Use custom key handler if provided, otherwise toggle selected flag
      local refresh = false
      if batch.actions.key_select then
        refresh = batch.actions.key_select(item)
      else
        item.selected = not item.selected
        refresh = true
      end

      -- Refresh display if needed
      if refresh then
        M.render_batch_dialog()
      end
    end
  end, opts)

  -- Toggle all: use select_all_task key
  popup:map("n", key_select_all, function()
    local cursor = vim.api.nvim_win_get_cursor(popup.winid)
    local row = cursor[1]

    -- Only toggle if on an item row
    if row >= 3 and row - 3 < #batch.data_items then
      local item_idx = row - 3
      local item = batch.data_items[item_idx + 1]
      local new_state = not item.selected

      -- Use custom handler if provided, otherwise toggle all items
      local refresh = false
      if batch.actions.key_select_all then
        refresh = batch.actions.key_select_all(item, new_state)
      else
        -- Set all to match
        for i, item in ipairs(batch.data_items) do
          item.selected = new_state
        end
        refresh = true
      end

      -- Refresh display if needed
      if refresh then
        M.render_batch_dialog()
      end
    end
  end, opts)

  -- Action key (for task-specific actions)
  if batch.mode == "task_list" or batch.mode == "tag_review" then
    popup:map("n", key_action, function()
      local cursor = vim.api.nvim_win_get_cursor(popup.winid)
      local row = cursor[1]

      -- Only act on item rows
      if row >= 3 and row - 3 < #batch.data_items then
        local item_idx = row - 3
        local item = batch.data_items[item_idx + 1]

        if batch.actions.key_action then
          local refresh = batch.actions.key_action(item)
          if refresh then
            M.render_batch_dialog()
          end
        end
      end
    end, opts)
  end

  -- Apply and exit: use quit key
  popup:map("n", key_quit, function()
    M.complete_dialog(false) -- Not cancelled
  end, opts)

  -- Cancel and exit: use unselect key
  popup:map("n", key_cancel, function()
    M.complete_dialog(true) -- Cancelled
  end, opts)

  -- Help: use help key
  popup:map("n", key_help, function()
    M.show_help_popup(options.help_config)
  end, opts)

  -- Jump to source on Enter
  popup:map("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(popup.winid)
    local row = cursor[1]

    -- Only jump if on an item row
    if row >= 3 and row - 3 < #batch.data_items then
      M.highlight_item_source(row - 3)
    end
  end, opts)

  -- Add task-specific actions if in relevant modes
  if batch.mode == "task_list" or batch.mode == "tag_review" then
    -- Edit
    popup:map("n", key_edit, function()
      local cursor = vim.api.nvim_win_get_cursor(popup.winid)
      local row = cursor[1]

      if row >= 3 and row - 3 < #batch.data_items then
        local item_idx = row - 3
        local item = batch.data_items[item_idx + 1]

        if batch.actions.key_edit then
          local refresh = batch.actions.key_edit(item)
          if refresh then
            M.render_batch_dialog()
          end
        end
      end
    end, opts)

    -- Done/complete
    popup:map("n", key_done, function()
      local cursor = vim.api.nvim_win_get_cursor(popup.winid)
      local row = cursor[1]

      if row >= 3 and row - 3 < #batch.data_items then
        local item_idx = row - 3
        local item = batch.data_items[item_idx + 1]

        if batch.actions.key_done then
          local refresh = batch.actions.key_done(item)
          if refresh then
            M.render_batch_dialog()
          end
        end
      end
    end, opts)

    -- Delete
    popup:map("n", key_delete, function()
      local cursor = vim.api.nvim_win_get_cursor(popup.winid)
      local row = cursor[1]

      if row >= 3 and row - 3 < #batch.data_items then
        local item_idx = row - 3
        local item = batch.data_items[item_idx + 1]

        if batch.actions.key_delete then
          local refresh = batch.actions.key_delete(item)
          if refresh then
            M.render_batch_dialog()
          end
        end
      end
    end, opts)
  end

  batch.visible = true
  return popup
end

-- Render the batch dialog with current data
function M.render_batch_dialog()
  if not ui_components.popup or not ui_components.popup.bufnr then
    return
  end

  local bufnr = ui_components.popup.bufnr

  -- Create content with header rows
  local content = {}

  -- Title row based on mode
  if batch.mode == "tag_select" then
    table.insert(content, "Select which tags to create tasks for:")
  elseif batch.mode == "tag_review" then
    table.insert(content, "Review tasks for tracked tags:")
  elseif batch.mode == "task_list" then
    table.insert(content, "Manage tasks:")
  else
    table.insert(content, "Select items:")
  end

  -- Add blank line before content
  table.insert(content, "")

  -- Generate column headers if needed
  if batch.mode == "task_list" or batch.mode == "tag_review" then
    local header_row = ""
    for _, col in ipairs(batch.columns) do
      if col == "select" then
        header_row = header_row .. "    " -- Space for checkbox
      elseif col == "tag" then
        header_row = header_row .. "TAG     "
      elseif col == "description" then
        header_row = header_row .. "DESCRIPTION                 "
      elseif col == "line" then
        header_row = header_row .. "LINE    "
      elseif col == "project" then
        header_row = header_row .. "PROJECT       "
      elseif col == "due" then
        header_row = header_row .. "DUE DATE   "
      elseif col == "priority" then
        header_row = header_row .. "PRI "
      elseif col == "status" then
        header_row = header_row .. "STATUS     "
      else
        -- Generic column
        header_row = header_row .. string.upper(col) .. "     "
      end
    end
    table.insert(content, header_row)
  end

  -- Format icons for selected/unselected
  local icons = get_icons()

  -- Generate rows for each item
  for i, item in ipairs(batch.data_items) do
    local row_content = ""

    -- Format the item using the formatter if available
    local formatted_item = item
    if batch.formatter then
      formatted_item = batch.formatter(item, i)
    end

    -- Build the row based on columns
    for _, col in ipairs(batch.columns) do
      if col == "select" then
        if formatted_item.select or formatted_item.selected then
          row_content = row_content .. "[" .. icons.selected .. "] "
        else
          row_content = row_content .. "[" .. icons.unselected .. "] "
        end
      elseif col == "tag" then
        local tag = formatted_item.tag or "TAG"
        row_content = row_content .. utils.clip_text(tag, 8) .. " "
      elseif col == "description" then
        local desc = formatted_item.description or ""
        row_content = row_content .. utils.clip_text(desc, 25) .. " "
      elseif col == "line" then
        local line = formatted_item.line or ""
        row_content = row_content .. line .. " "
      elseif col == "project" then
        local project = formatted_item.project or ""
        row_content = row_content .. utils.clip_text(project, 12) .. " "
      elseif col == "due" then
        local due = formatted_item.due or ""
        row_content = row_content .. utils.clip_text(due, 10) .. " "
      elseif col == "priority" then
        local priority = formatted_item.priority or ""
        row_content = row_content .. priority .. " "
      elseif col == "status" then
        local status = formatted_item.status or "pending"
        row_content = row_content .. utils.clip_text(status, 10) .. " "
      else
        -- Generic column
        local value = formatted_item[col] or ""
        if type(value) == "string" then
          row_content = row_content .. utils.clip_text(value, 10) .. " "
        else
          row_content = row_content .. tostring(value) .. " "
        end
      end
    end

    table.insert(content, row_content)
  end

  -- Set buffer content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

  -- Apply highlighting
  vim.api.nvim_buf_add_highlight(bufnr, -1, "Title", 0, 0, -1)

  -- Highlight column headers if present
  if batch.mode == "task_list" or batch.mode == "tag_review" then
    vim.api.nvim_buf_add_highlight(bufnr, -1, "Special", 2, 0, -1)
  end

  -- Clear previous namespace highlights
  vim.api.nvim_buf_clear_namespace(bufnr, batch.namespace, 0, -1)

  -- Highlight individual items
  local header_offset = (batch.mode == "task_list" or batch.mode == "tag_review") and 3 or 2

  for i = 1, #batch.data_items do
    local line_idx = i + header_offset - 1
    local line = content[line_idx + 1]

    -- Highlight checkbox
    if line and line:sub(1, 1) == "[" then
      if line:sub(2, 2) == icons.selected then
        vim.api.nvim_buf_add_highlight(bufnr, batch.namespace, "DiagnosticOk", line_idx, 0, 3)
      else
        vim.api.nvim_buf_add_highlight(bufnr, batch.namespace, "DiagnosticError", line_idx, 0, 3)
      end
    end

    -- Highlight tag column if present
    local tag_start = line and line:find("[A-Z]+") or nil
    if tag_start and tag_start > 3 then
      local tag_end = line:find(" ", tag_start) or tag_start + 8
      vim.api.nvim_buf_add_highlight(bufnr, batch.namespace, "Type", line_idx, tag_start - 1, tag_end)
    end

    -- Highlight priority if present
    if vim.tbl_contains(batch.columns, "priority") then
      local col_idx = 0
      for j, col in ipairs(batch.columns) do
        if col == "priority" then
          col_idx = j
          break
        end
      end

      if col_idx > 0 then
        -- Calculate approximate position of priority column
        local pos = 4 -- Checkbox width
        for j = 1, col_idx - 1 do
          if batch.columns[j] == "tag" then
            pos = pos + 8
          elseif batch.columns[j] == "description" then
            pos = pos + 25
          elseif batch.columns[j] == "line" then
            pos = pos + 8
          elseif batch.columns[j] == "project" then
            pos = pos + 12
          elseif batch.columns[j] == "due" then
            pos = pos + 10
          elseif batch.columns[j] == "status" then
            pos = pos + 10
          else
            pos = pos + 10
          end
        end

        local priority = batch.data_items[i].priority or ""
        if priority == "H" then
          vim.api.nvim_buf_add_highlight(bufnr, batch.namespace, "ErrorMsg", line_idx, pos, pos + 1)
        elseif priority == "M" then
          vim.api.nvim_buf_add_highlight(bufnr, batch.namespace, "WarningMsg", line_idx, pos, pos + 1)
        elseif priority == "L" then
          vim.api.nvim_buf_add_highlight(bufnr, batch.namespace, "Comment", line_idx, pos, pos + 1)
        end
      end
    end

    -- Highlight status if present
    if vim.tbl_contains(batch.columns, "status") then
      local col_idx = 0
      for j, col in ipairs(batch.columns) do
        if col == "status" then
          col_idx = j
          break
        end
      end

      if col_idx > 0 then
        -- Calculate approximate position of status column
        local pos = 4 -- Checkbox width
        for j = 1, col_idx - 1 do
          if batch.columns[j] == "tag" then
            pos = pos + 8
          elseif batch.columns[j] == "description" then
            pos = pos + 25
          elseif batch.columns[j] == "line" then
            pos = pos + 8
          elseif batch.columns[j] == "project" then
            pos = pos + 12
          elseif batch.columns[j] == "due" then
            pos = pos + 10
          elseif batch.columns[j] == "priority" then
            pos = pos + 5
          else
            pos = pos + 10
          end
        end

        local status = batch.data_items[i].status or ""
        local status_len = string.len(status)

        if status == "completed" or status == "done" then
          vim.api.nvim_buf_add_highlight(bufnr, batch.namespace, "DiagnosticOk", line_idx, pos, pos + status_len)
        elseif status == "pending" then
          vim.api.nvim_buf_add_highlight(bufnr, batch.namespace, "WarningMsg", line_idx, pos, pos + status_len)
        elseif status == "deleted" then
          vim.api.nvim_buf_add_highlight(bufnr, batch.namespace, "DiagnosticError", line_idx, pos, pos + status_len)
        end
      end
    end
  end
end

-- Highlight the source item in the original buffer
function M.highlight_item_source(item_idx)
  if not batch.source_bufnr or not vim.api.nvim_buf_is_valid(batch.source_bufnr) then
    return false
  end

  -- Get the item
  local item = batch.data_items[item_idx + 1]
  if not item then
    return false
  end

  -- Extract line number from item
  local lnum = item.lnum
  if not lnum then
    if item._data and item._data.lnum then
      lnum = item._data.lnum
    else
      return false
    end
  end

  -- Jump to the tag in the source buffer
  local buffer = require("taskforge.tracker.buffer")
  buffer.jump_to_tag(batch.source_bufnr, lnum)

  -- Create highlight namespace if needed
  if not batch.highlight_namespace then
    batch.highlight_namespace = vim.api.nvim_create_namespace("taskforge_tag_highlight")
  end

  -- Clear previous highlights
  vim.api.nvim_buf_clear_namespace(batch.source_bufnr, batch.highlight_namespace, 0, -1)

  -- Add highlight to the source line
  local cfg = config.get().interface.batch_ui or {}
  if cfg.highlight_line ~= false then
    vim.api.nvim_buf_add_highlight(batch.source_bufnr, batch.highlight_namespace, "Visual", lnum, 0, -1)
  end

  -- Focus back to the dialog if it's active
  if ui_components.popup and ui_components.popup.winid and vim.api.nvim_win_is_valid(ui_components.popup.winid) then
    vim.api.nvim_set_current_win(ui_components.popup.winid)
  end

  return true
end

-- Complete the dialog and call the completion callback
function M.complete_dialog(cancelled)
  -- Call completion callback if provided
  if batch.on_complete then
    batch.on_complete(batch.data_items, cancelled)
  end

  -- Close the UI
  M.close_dialog()
end

-- Close the batch dialog
function M.close_dialog()
  -- Clear highlight in buffer
  if batch.highlight_namespace and batch.source_bufnr and vim.api.nvim_buf_is_valid(batch.source_bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, batch.source_bufnr, batch.highlight_namespace, 0, -1)
  end

  -- Unmount popup if visible
  if ui_components.popup then
    pcall(function()
      ui_components.popup:unmount()
    end)
    ui_components.popup = nil
  end

  -- Reset batch state
  batch.active = false
  batch.visible = false
  batch.data_items = {}
  batch.source_bufnr = nil

  debug.log("UI", "Dialog closed")
end

-- Simple selection UI fallback for when NUI is not available
function M.show_simple_selection(options)
  local items = options.data_items or {}
  if #items == 0 then
    utils.notify("No items to process")
    return
  end

  -- Format items for selection
  local formatted_items = {}
  for i, item in ipairs(items) do
    local formatted = options.item_formatter and options.item_formatter(item, i) or item

    table.insert(formatted_items, {
      text = string.format(
        "[%s] %s: %s",
        formatted.selected and "✓" or "✗",
        formatted.tag or "",
        formatted.description or ""
      ),
      index = i,
      item = item,
      _data = formatted._data or item,
    })
  end

  -- Show UI selector
  vim.ui.select(formatted_items, {
    prompt = options.title or "Select items:",
    format_item = function(item)
      return item.text
    end,
  }, function(selected)
    if selected and options.source_bufnr and selected._data and selected._data.lnum then
      -- Jump to the selected tag
      local buffer = require("taskforge.tracker.buffer")
      buffer.jump_to_tag(options.source_bufnr, selected._data.lnum)

      -- Process selection
      if options.on_complete then
        local item = items[selected.index]
        item.selected = not item.selected
        options.on_complete({ item }, false)
      end
    end
  end)
end

-- Review tags in a buffer
function M.review_tags_in_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Get all tags in the buffer
  local cached_tags = core.get_all_cached_tags(bufnr)
  if not cached_tags or vim.tbl_isempty(cached_tags) then
    utils.notify("No tags found in buffer", vim.log.levels.INFO)
    return
  end

  -- Convert to list format
  local tags = {}
  for lnum, tag_data in pairs(cached_tags) do
    local item = {
      lnum = lnum,
      text = tag_data.text,
      tag_name = tag_data.tag_name,
      uuid = tag_data.uuid,
      selected = false,
    }

    -- If there's a UUID, fetch task info
    if tag_data.uuid then
      local tasks = require("taskforge.tasks")
      local task = tasks.get_task(tag_data.uuid)
      if task then
        item.task = task
        item.description = task.description
        item.project = task.project
        item.priority = task.priority
        item.due = task.due
        item.status = task.status
      else
        item.description = "Task not found"
      end
    else
      item.description = tag_data.text:sub(1, 40)
    end

    table.insert(tags, item)
  end

  -- Sort by line number
  table.sort(tags, function(a, b)
    return a.lnum < b.lnum
  end)

  -- Show tags in review dialog
  M.show_batch_dialog({
    source_bufnr = bufnr,
    data_items = tags,
    mode = "tag_review",
    title = "Tag Review",
    columns = { "select", "tag", "description", "line", "status" },
    item_formatter = function(item, idx)
      return {
        select = item.selected,
        tag = item.tag_name or "TAG",
        description = item.description or "",
        line = "line " .. (item.lnum + 1),
        status = item.status or "pending",
        _data = item,
      }
    end,
    key_select = function(item)
      item.selected = not item.selected
      return true
    end,
    key_done = function(item)
      if item.uuid then
        require("taskforge.tasks").done(item.uuid)
        item.status = "completed"
        return true
      end
      return false
    end,
    on_complete = function(items, cancelled)
      if not cancelled then
        -- Handle selected items (e.g., batch operations)
        local selected = {}
        for _, item in ipairs(items) do
          if item.selected then
            table.insert(selected, item)
          end
        end

        if #selected > 0 then
          utils.notify(string.format("Selected %d tags", #selected))
          -- Perform batch operations if needed
        end
      end
    end,
  })
end

-- Add emergency exit command
function M.setup_emergency_exit()
  vim.api.nvim_create_user_command("TaskforgeUIClose", function()
    M.close_dialog()
    utils.notify("UI forcibly closed")
  end, {})
end

return M

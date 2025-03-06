-- lua/taskforge/ui/batch.lua
--
--
-- Batch processing dialog for tag handling

local M = {}
local utils = require("taskforge.utils")
local ui_utils = require("taskforge.ui.utils")
local dialog = require("taskforge.ui.dialog")
local config = require("taskforge.config")
local debug = require("taskforge.debug")

-- Module state for batch processing
local state = {
  active = false,
  current_dialog = nil,
  data_items = {},
  source_bufnr = nil,
  highlight_namespace = nil,
  mode = "tag_select", -- "tag_select", "tag_review", "task_list"
  columns = {},
  actions = {},
  formatter = nil,
  on_complete = nil,
  processing_lock = {}, -- Buffer-specific processing lock
}

-- Process a batch of tag candidates
-- @param bufnr number Buffer number
-- @param candidates table Array of tag candidates
function M.process_tags(bufnr, candidates)
  debug.log("BATCH", "Processing " .. #candidates .. " tag candidates")

  -- Check if we're already processing this buffer to prevent recursion
  if state.processing_lock[bufnr] then
    debug.log("BATCH", "Already processing buffer " .. bufnr .. ", skipping")
    return
  end

  -- Set processing lock
  state.processing_lock[bufnr] = true

  -- Group candidates by type for processing
  local buffer = require("taskforge.tracker.buffer")
  local result = buffer.process_candidates_by_type(bufnr, candidates)

  -- Report auto-processed
  if result.auto_processed > 0 then
    utils.notify(string.format("%d tags processed automatically", result.auto_processed), vim.log.levels.INFO)
  end

  -- If there are interactive tags to handle, show the UI
  if #result.interactive > 0 then
    debug.log("BATCH", "Found " .. #result.interactive .. " interactive tags")

    -- We need to delay showing the UI to prevent focus issues
    vim.schedule(function()
      M.show_dialog({
        source_bufnr = bufnr,
        data_items = result.interactive,
        mode = "tag_select",
        title = "Select Tags to Create",
        columns = { "select", "tag", "description", "line" },
        item_formatter = function(item, idx)
          return {
            select = item.selected,
            tag = item.tag,
            description = item.description or "No description",
            line = "line " .. (item.lnum + 1),
            _data = item,
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
          -- Release buffer processing lock
          state.processing_lock[bufnr] = nil
        end,
      })
    end)
  elseif result.manual_processed > 0 or result.auto_processed > 0 then
    local msg = ""
    if result.auto_processed > 0 then
      msg = msg .. string.format("%d tags processed automatically. ", result.auto_processed)
    end
    if result.manual_processed > 0 then
      msg = msg .. string.format("%d tags prepared for manual handling.", result.manual_processed)
    end
    utils.notify(msg, vim.log.levels.INFO)

    -- Release buffer processing lock
    state.processing_lock[bufnr] = nil
  else
    utils.notify("No tags found to process", vim.log.levels.INFO)

    -- Release buffer processing lock
    state.processing_lock[bufnr] = nil
  end
end

-- Apply tag selections after batch processing
-- @param bufnr number Buffer number
-- @param items table Array of selected items
function M.apply_tag_selections(bufnr, items)
  -- Process selected tags
  local processed = 0
  local optout = 0
  local buffer = require("taskforge.tracker.buffer")
  local tags = require("taskforge.tracker.tags")

  -- Validate items
  if not items or #items == 0 then
    utils.notify("No items to process", vim.log.levels.WARN)
    return
  end

  -- Progress indicator
  local total_items = #items
  local progress_msg = "Processing tags "
  utils.notify(progress_msg .. "(0/" .. total_items .. ")", vim.log.levels.INFO)

  -- Process items with progress updates
  for i, item in ipairs(items) do
    if item.selected then
      -- Create task from tag
      buffer.process_auto_tag(bufnr, item._data)
      processed = processed + 1
    else
      -- Add opt-out marker to tag
      tags.add_optout_marker(bufnr, item._data.lnum)
      optout = optout + 1
    end

    -- Update progress every few items
    if i % 5 == 0 then
      utils.notify(progress_msg .. "(" .. i .. "/" .. total_items .. ")", vim.log.levels.INFO)
    end
  end

  -- Track that the buffer has been batch processed
  local tracker = require("taskforge.tracker.core")
  tracker.set_buffer_batch_processed(bufnr)

  -- Notify results
  if processed > 0 or optout > 0 then
    local msg = string.format("Processed %d tags, marked %d tags as [notrack]", processed, optout)
    utils.notify(msg, vim.log.levels.INFO)
  end
end

-- Show batch processing dialog
-- @param options table Dialog options
function M.show_dialog(options)
  -- Ensure we have NUI
  local has_nui, _ = pcall(require, "nui.popup")
  if not has_nui then
    utils.notify("Batch UI requires nui.nvim", vim.log.levels.WARN)
    -- Fall back to simple selection
    M.show_simple_selection(options)
    return
  end

  debug.log("BATCH", "Opening batch dialog", options.title or "")

  -- Set up internal state
  state.active = true
  state.data_items = options.data_items or {}
  state.source_bufnr = options.source_bufnr
  state.mode = options.mode or "tag_select"
  state.columns = options.columns or { "select", "tag", "description", "line" }
  state.formatter = options.item_formatter
  state.on_complete = options.on_complete
  state.actions = {
    key_select = options.key_select,
    key_select_all = options.key_select_all,
    key_action = options.key_action,
    key_edit = options.key_edit,
    key_done = options.key_done,
    key_delete = options.key_delete,
  }

  -- Prevent cleanup during creation
  local already_processing = true

  -- Get configuration for keymaps
  local cfg = config.get()
  local keymaps = (cfg.interface and cfg.interface.keymaps) or {}

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

  -- Additional keys for task management modes
  local key_edit = keymaps.edit or "e"
  local key_done = keymaps.close_task or "d"
  local key_delete = keymaps.delete_task or "-"

  -- Format footer text based on mode
  local footer_text
  if state.mode == "tag_select" then
    footer_text = string.format(
      "%s: Apply | %s: Cancel | %s: Help",
      ui_utils.format_key(key_quit),
      ui_utils.format_key(key_cancel),
      ui_utils.format_key(key_help)
    )
  elseif state.mode == "task_list" or state.mode == "tag_review" then
    footer_text = string.format(
      "%s: Apply | %s: Edit | %s: Done | %s: Delete | %s: Help",
      ui_utils.format_key(key_quit),
      ui_utils.format_key(key_edit),
      ui_utils.format_key(key_done),
      ui_utils.format_key(key_delete),
      ui_utils.format_key(key_help)
    )
  end

  -- Get batch UI config
  local batch_cfg = (cfg.interface and cfg.interface.batch_ui) or {}

  -- Calculate size options
  local size_options = {
    width_percent = batch_cfg.width_percent or 80,
    height_percent = batch_cfg.height_percent or 20,
    max_width = batch_cfg.max_width or 80,
    max_height = batch_cfg.max_height or 20,
    min_width = batch_cfg.min_width or 50,
    min_height = batch_cfg.min_height or 5,
    position = batch_cfg.position or "top",
  }

  -- Calculate actual size
  local size = ui_utils.calculate_size(size_options)

  -- Setup dialog keymaps
  local dialog_keymaps = {
    -- Close without applying
    [key_cancel] = function(dlg)
      M.complete_dialog(true) -- Cancelled
    end,

    -- Apply and close
    [key_quit] = function(dlg)
      M.complete_dialog(false) -- Not cancelled
    end,

    -- Show help
    [key_help] = function(dlg)
      local help = require("taskforge.ui.help")
      help.show_dialog_help(dlg)
    end,

    -- Toggle item
    [key_select] = function(dlg)
      local cursor = vim.api.nvim_win_get_cursor(dlg.popup.winid)
      local row = cursor[1]

      local header_rows = (state.mode == "tag_select") and 2 or 3

      -- Only toggle item rows, not headers
      if row >= header_rows and row - header_rows < #state.data_items then
        local item_idx = row - header_rows
        local item = state.data_items[item_idx + 1]

        -- Use custom handler or default toggle
        local refresh = false
        if state.actions.key_select then
          refresh = state.actions.key_select(item)
        else
          item.selected = not item.selected
          refresh = true
        end

        -- Refresh if needed
        if refresh then
          M.render_dialog(dlg)
        end
      end
    end,

    -- Toggle all items
    [key_select_all] = function(dlg)
      local cursor = vim.api.nvim_win_get_cursor(dlg.popup.winid)
      local row = cursor[1]

      local header_rows = (state.mode == "tag_select") and 2 or 3

      -- Only toggle if on an item row
      if row >= header_rows and row - header_rows < #state.data_items then
        local item_idx = row - header_rows
        local item = state.data_items[item_idx + 1]
        local new_state = not item.selected

        -- Use custom handler or default toggle all
        local refresh = false
        if state.actions.key_select_all then
          refresh = state.actions.key_select_all(item, new_state)
        else
          -- Toggle all to match
          for _, data_item in ipairs(state.data_items) do
            data_item.selected = new_state
          end
          refresh = true
        end

        -- Refresh if needed
        if refresh then
          M.render_dialog(dlg)
        end
      end
    end,
  }

  -- Add movement keys for up/down (handle both string and array keys)
  local up_keys = type(keymaps.up) == "table" and keymaps.up or { keymaps.up or "k", "<Up>" }
  local down_keys = type(keymaps.down) == "table" and keymaps.down or { keymaps.down or "j", "<Down>" }

  for _, key in ipairs(type(up_keys) == "table" and up_keys or { up_keys }) do
    dialog_keymaps[key] = function(dlg)
      local cursor = vim.api.nvim_win_get_cursor(dlg.popup.winid)
      local row = cursor[1]
      local header_rows = (state.mode == "tag_select") and 2 or 3

      -- Don't go above first item row
      if row > header_rows then
        vim.api.nvim_win_set_cursor(dlg.popup.winid, { row - 1, 0 })
        M.highlight_item_source(row - header_rows - 1) -- After moving up
      end
    end
  end

  for _, key in ipairs(type(down_keys) == "table" and down_keys or { down_keys }) do
    dialog_keymaps[key] = function(dlg)
      local cursor = vim.api.nvim_win_get_cursor(dlg.popup.winid)
      local row = cursor[1]
      local header_rows = (state.mode == "tag_select") and 2 or 3

      -- Don't go past the last item
      local content_len = #state.data_items + header_rows - 1
      if row < content_len + 1 then
        vim.api.nvim_win_set_cursor(dlg.popup.winid, { row + 1, 0 })
        M.highlight_item_source(row - header_rows + 1) -- After moving down
      end
    end
  end

  -- Add task-specific actions for relevant modes
  if state.mode == "task_list" or state.mode == "tag_review" then
    -- Add task management keymaps
    dialog_keymaps[key_edit] = M._create_edit_handler()
    dialog_keymaps[key_done] = M._create_done_handler()
    dialog_keymaps[key_delete] = M._create_delete_handler()
  end

  -- Add Enter key to jump to source
  dialog_keymaps["<CR>"] = function(dlg)
    local cursor = vim.api.nvim_win_get_cursor(dlg.popup.winid)
    local row = cursor[1]
    local header_rows = (state.mode == "tag_select") and 2 or 3

    if row >= header_rows and row - header_rows < #state.data_items then
      M.highlight_item_source(row - header_rows)
    end
  end

  -- Create dialog
  local batch_dialog = dialog.create({
    title = options.title or "Batch Processing",
    mode = "batch",

    -- Size and position
    position = {
      row = size.row,
      col = size.col,
    },
    size = {
      width = size.width,
      height = size.height,
    },

    -- Style
    border_style = "rounded",
    win_options = {
      cursorline = true,
    },

    -- Behavior
    keymaps = dialog_keymaps,

    -- Custom properties
    columns = state.columns,

    -- Custom render function
    render = function(dialog)
      M.render_dialog(dialog)
    end,

    -- Events
    on_close = function(dlg)
      if not already_processing then
        debug.log("BATCH", "Dialog closed via event")
        M.cleanup()
      else
        debug.log("BATCH", "Ignoring close during initialization")
      end
    end,

    -- Border text
    border = {
      text = {
        top = " " .. (options.title or "Batch Processing") .. " ",
        top_align = "center",
        bottom = " " .. footer_text .. " ",
        bottom_align = "center",
      },
    },
  })

  -- Store reference to dialog
  state.current_dialog = batch_dialog

  -- Set up highlight namespace
  state.highlight_namespace = vim.api.nvim_create_namespace("taskforge_batch_highlight")

  -- Force cursor to first item row and focus window
  vim.schedule(function()
    already_processing = false

    if batch_dialog.popup and vim.api.nvim_win_is_valid(batch_dialog.popup.winid) then
      debug.log("BATCH", "Setting initial cursor position and focus")

      -- Force focus to the dialog window
      vim.api.nvim_set_current_win(batch_dialog.popup.winid)

      local header_rows = (state.mode == "tag_select") and 2 or 3
      vim.api.nvim_win_set_cursor(batch_dialog.popup.winid, { header_rows, 0 })

      -- Highlight source if we have items
      if #state.data_items > 0 then
        M.highlight_item_source(0)
      end
    else
      debug.log("BATCH", "Dialog invalid after initialization")
    end
  end)

  return batch_dialog
end

-- Create handler for edit action
function M._create_edit_handler()
  return function(dlg)
    local cursor = vim.api.nvim_win_get_cursor(dlg.popup.winid)
    local row = cursor[1]
    local header_rows = 3 -- These modes have headers

    if row >= header_rows and row - header_rows < #state.data_items then
      local item_idx = row - header_rows
      local item = state.data_items[item_idx + 1]

      if state.actions.key_edit then
        local refresh = state.actions.key_edit(item)
        if refresh then
          M.render_dialog(dlg)
        end
      end
    end
  end
end

-- Create handler for done action
function M._create_done_handler()
  return function(dlg)
    local cursor = vim.api.nvim_win_get_cursor(dlg.popup.winid)
    local row = cursor[1]
    local header_rows = 3

    if row >= header_rows and row - header_rows < #state.data_items then
      local item_idx = row - header_rows
      local item = state.data_items[item_idx + 1]

      if state.actions.key_done then
        local refresh = state.actions.key_done(item)
        if refresh then
          M.render_dialog(dlg)
        end
      end
    end
  end
end

-- Create handler for delete action
function M._create_delete_handler()
  return function(dlg)
    local cursor = vim.api.nvim_win_get_cursor(dlg.popup.winid)
    local row = cursor[1]
    local header_rows = 3

    if row >= header_rows and row - header_rows < #state.data_items then
      local item_idx = row - header_rows
      local item = state.data_items[item_idx + 1]

      if state.actions.key_delete then
        local refresh = state.actions.key_delete(item)
        if refresh then
          M.render_dialog(dlg)
        end
      end
    end
  end
end

-- Render the batch dialog content
-- @param dialog table Dialog object
function M.render_dialog(dialog)
  if not dialog or not dialog.popup or not dialog.popup.bufnr then
    return
  end

  local bufnr = dialog.popup.bufnr

  -- Make buffer modifiable
  vim.bo[bufnr].modifiable = true

  -- Clear buffer
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

  -- Get icons
  local icons = ui_utils.get_ui_icons()

  -- Create content based on mode
  local content = {}

  -- Title line based on mode
  if state.mode == "tag_select" then
    table.insert(content, "Select which tags to create tasks for:")
  elseif state.mode == "tag_review" then
    table.insert(content, "Review tasks for tracked tags:")
  elseif state.mode == "task_list" then
    table.insert(content, "Manage tasks:")
  else
    table.insert(content, "Select items:")
  end

  -- Add blank line before content
  table.insert(content, "")

  -- Add column headers for list modes
  if state.mode == "task_list" or state.mode == "tag_review" then
    local header_row = ""

    -- Calculate column widths
    local col_widths = {}
    for _, col in ipairs(state.columns) do
      if col == "select" then
        col_widths[col] = 4 -- Space for checkbox
      elseif col == "tag" then
        col_widths[col] = 8
      elseif col == "description" then
        col_widths[col] = 30
      elseif col == "line" then
        col_widths[col] = 8
      elseif col == "project" then
        col_widths[col] = 15
      elseif col == "due" then
        col_widths[col] = 10
      elseif col == "priority" then
        col_widths[col] = 4
      elseif col == "status" then
        col_widths[col] = 10
      else
        col_widths[col] = 10
      end
    end

    -- Generate header row with column names
    for _, col in ipairs(state.columns) do
      if col == "select" then
        header_row = header_row .. "    " -- Space for checkbox
      else
        local width = col_widths[col] or 10
        local col_name = string.upper(col)
        header_row = header_row .. col_name .. string.rep(" ", width - #col_name) .. " "
      end
    end

    table.insert(content, header_row)
  end

  -- Generate item rows
  for i, item in ipairs(state.data_items) do
    local row_content = ""

    -- Format the item using formatter if available
    local formatted_item = item
    if state.formatter then
      formatted_item = state.formatter(item, i)
    end

    -- Build row based on columns
    for _, col in ipairs(state.columns) do
      if col == "select" then
        local checkbox = formatted_item.select
          or formatted_item.selected and "[" .. icons.selected .. "] "
          or "[" .. icons.unselected .. "] "
        row_content = row_content .. checkbox
      elseif col == "tag" then
        local tag = formatted_item.tag or "TAG"
        row_content = row_content .. utils.clip_text(tag, 8) .. " "
      elseif col == "description" then
        local desc = formatted_item.description or ""
        row_content = row_content .. utils.clip_text(desc, 30) .. " "
      elseif col == "line" then
        local line = formatted_item.line or ""
        row_content = row_content .. line .. " "
      elseif col == "project" then
        local project = formatted_item.project or ""
        row_content = row_content .. utils.clip_text(project, 15) .. " "
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
  if state.mode == "task_list" or state.mode == "tag_review" then
    vim.api.nvim_buf_add_highlight(bufnr, -1, "Special", 2, 0, -1)
  end

  -- Clear previous namespace highlights
  vim.api.nvim_buf_clear_namespace(bufnr, dialog.namespace, 0, -1)

  -- Apply custom highlighting to items
  M._apply_item_highlighting(bufnr, content, dialog.namespace)

  -- Make buffer non-modifiable
  vim.bo[bufnr].modifiable = false
end

-- Apply custom highlighting to items
-- @param bufnr number Buffer number
-- @param content table Content lines
-- @param namespace number Highlight namespace
function M._apply_item_highlighting(bufnr, content, namespace)
  -- Get icons for selection
  local icons = ui_utils.get_ui_icons()

  -- Determine header offset
  local header_offset = (state.mode == "task_list" or state.mode == "tag_review") and 3 or 2

  -- Apply highlights to each item
  for i = 1, #state.data_items do
    local line_idx = i + header_offset - 1
    local line = content[line_idx + 1]
    local item = state.data_items[i]

    -- Skip if invalid line
    if not line then
      goto continue
    end

    -- Highlight checkbox
    if line:sub(1, 1) == "[" then
      if line:sub(2, 2) == icons.selected then
        vim.api.nvim_buf_add_highlight(bufnr, namespace, "DiagnosticOk", line_idx, 0, 3)
      else
        vim.api.nvim_buf_add_highlight(bufnr, namespace, "DiagnosticError", line_idx, 0, 3)
      end
    end

    -- Highlight tag column if present
    local tag_start = line and line:find("[A-Z]+") or nil
    if tag_start and tag_start > 3 then
      local tag_end = line:find(" ", tag_start) or tag_start + 8
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "Type", line_idx, tag_start - 1, tag_end)
    end

    -- Highlight priority if present
    local priority = item.priority or ""
    if priority ~= "" and vim.tbl_contains(state.columns, "priority") then
      -- Calculate position of priority in the line
      local col_pos = M._get_column_position("priority")
      if col_pos then
        if priority == "H" then
          vim.api.nvim_buf_add_highlight(bufnr, namespace, "ErrorMsg", line_idx, col_pos, col_pos + 1)
        elseif priority == "M" then
          vim.api.nvim_buf_add_highlight(bufnr, namespace, "WarningMsg", line_idx, col_pos, col_pos + 1)
        elseif priority == "L" then
          vim.api.nvim_buf_add_highlight(bufnr, namespace, "Comment", line_idx, col_pos, col_pos + 1)
        end
      end
    end

    -- Highlight status if present
    local status = item.status or ""
    if status ~= "" and vim.tbl_contains(state.columns, "status") then
      -- Calculate position of status in the line
      local col_pos = M._get_column_position("status")
      if col_pos then
        if status == "completed" or status == "done" then
          vim.api.nvim_buf_add_highlight(bufnr, namespace, "DiagnosticOk", line_idx, col_pos, col_pos + #status)
        elseif status == "pending" then
          vim.api.nvim_buf_add_highlight(bufnr, namespace, "WarningMsg", line_idx, col_pos, col_pos + #status)
        elseif status == "deleted" then
          vim.api.nvim_buf_add_highlight(bufnr, namespace, "DiagnosticError", line_idx, col_pos, col_pos + #status)
        end
      end
    end

    ::continue::
  end
end

-- Calculate position of a column in the display line
-- @param column_name string Column name
-- @return number|nil Column position
function M._get_column_position(column_name)
  -- Calculate approximate column position
  local col_idx = nil
  for i, col in ipairs(state.columns) do
    if col == column_name then
      col_idx = i
      break
    end
  end

  if not col_idx then
    return nil
  end

  -- Calculate position
  local pos = 0
  for i = 1, col_idx - 1 do
    local col = state.columns[i]
    if col == "select" then
      pos = pos + 4
    elseif col == "tag" then
      pos = pos + 9
    elseif col == "description" then
      pos = pos + 31
    elseif col == "line" then
      pos = pos + 9
    elseif col == "project" then
      pos = pos + 16
    elseif col == "due" then
      pos = pos + 11
    elseif col == "priority" then
      pos = pos + 5
    elseif col == "status" then
      pos = pos + 11
    else
      pos = pos + 11
    end
  end

  return pos
end

-- Highlight source item in original buffer
-- @param item_idx number Item index (0-based)
-- @return boolean Success
function M.highlight_item_source(item_idx)
  if not state.source_bufnr or not vim.api.nvim_buf_is_valid(state.source_bufnr) then
    return false
  end

  -- Get the item
  local item = state.data_items[item_idx + 1]
  if not item then
    return false
  end

  -- Extract line number
  local lnum = item.lnum
  if not lnum then
    if item._data and item._data.lnum then
      lnum = item._data.lnum
    else
      return false
    end
  end

  -- Jump to tag in source buffer
  local buffer = require("taskforge.tracker.buffer")
  buffer.jump_to_tag(state.source_bufnr, lnum)

  -- Create highlight namespace if needed
  if not state.highlight_namespace then
    state.highlight_namespace = vim.api.nvim_create_namespace("taskforge_batch_source_highlight")
  end

  -- Clear previous highlights - add validation
  if
    type(state.source_bufnr) == "number"
    and type(state.highlight_namespace) == "number"
    and vim.api.nvim_buf_is_valid(state.source_bufnr)
  then
    vim.api.nvim_buf_clear_namespace(state.source_bufnr, state.highlight_namespace, 0, -1)
  end

  -- Add highlight to source line
  local cfg = config.get()
  local highlight_line = true
  if cfg.interface and cfg.interface.batch_ui and cfg.interface.batch_ui.highlight_line == false then
    highlight_line = false
  end

  if highlight_line and type(state.source_bufnr) == "number" and vim.api.nvim_buf_is_valid(state.source_bufnr) then
    vim.api.nvim_buf_add_highlight(state.source_bufnr, state.highlight_namespace, "Visual", lnum, 0, -1)
  end

  -- Return focus to dialog
  if
    state.current_dialog
    and state.current_dialog.popup
    and state.current_dialog.popup.winid
    and vim.api.nvim_win_is_valid(state.current_dialog.popup.winid)
  then
    vim.api.nvim_set_current_win(state.current_dialog.popup.winid)
  end

  return true
end

-- Complete batch dialog and call completion callback
-- @param cancelled boolean Whether dialog was cancelled
function M.complete_dialog(cancelled)
  -- Call completion callback if available
  if state.on_complete then
    state.on_complete(state.data_items, cancelled)
  end

  -- Close dialog if it exists
  if state.current_dialog then
    state.current_dialog:close()
  end
end

-- Clean up resources
function M.cleanup()
  -- Clear highlight in source buffer
  if
    state.highlight_namespace
    and type(state.source_bufnr) == "number"
    and state.source_bufnr
    and vim.api.nvim_buf_is_valid(state.source_bufnr)
  then
    pcall(vim.api.nvim_buf_clear_namespace, state.source_bufnr, state.highlight_namespace, 0, -1)
  end

  -- Reset state
  state.active = false
  state.current_dialog = nil
  state.data_items = {}
  state.source_bufnr = nil
  state.highlight_namespace = nil

  debug.log("BATCH", "Batch dialog resources cleaned up")
end

-- Review tags in a buffer
function M.review_tags_in_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Get cached tags for buffer
  local core = require("taskforge.tracker.core")
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

    -- If UUID exists, fetch task info
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
  M.show_dialog({
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

return M

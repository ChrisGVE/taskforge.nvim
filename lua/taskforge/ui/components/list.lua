-- lua/taskforge/ui/components/list.lua
--
-- Reusable list component for Taskforge UI

local M = {}
local utils = require("taskforge.utils")
local ui_utils = require("taskforge.ui.utils")
local config = require("taskforge.config")
local icons = require("taskforge.ui.icons")

-- Create a new list component
-- @param dialog table Parent dialog object
-- @param options table Configuration options
-- @return table List component
function M.create(dialog, options)
  options = options or {}

  local list = {
    dialog = dialog,
    items = options.items or {},
    selected_index = options.selected_index or 1,
    multi_select = options.multi_select or false,
    selected_items = options.selected_items or {},

    -- Formatting
    formatter = options.formatter,
    column_widths = options.column_widths or {},
    columns = options.columns or { "select", "description" },

    -- Position and size
    row = options.row or 0,
    col = options.col or 0,
    width = options.width or 0,
    height = options.height or 0,

    -- Callbacks
    on_select = options.on_select,
    on_submit = options.on_submit,
    on_toggle = options.on_toggle,

    -- Namespace for highlights
    namespace = vim.api.nvim_create_namespace("taskforge_list_" .. tostring(math.random(1000000))),

    -- State
    header_rows = options.header_rows or (options.show_header and 1 or 0),
    footer_rows = options.footer_rows or 0,
    scroll_offset = 0,
  }

  -- Calculate height if not specified
  if list.height <= 0 then
    list.height = #list.items + list.header_rows + list.footer_rows
  end

  -- Add methods

  -- Render list
  list.render = function(self)
    if not self.dialog or not self.dialog.popup or not self.dialog.popup.bufnr then
      return self
    end

    local bufnr = self.dialog.popup.bufnr

    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

    -- Clear buffer (or just the region for this list)
    if self.row == 0 and self.height == vim.api.nvim_buf_line_count(bufnr) then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    else
      vim.api.nvim_buf_set_lines(bufnr, self.row, self.row + self.height, false, {})
    end

    -- Get icon set
    local icon_set = icons.get_all()

    -- Prepare content
    local content = {}

    -- Add header if needed
    if self.header_rows > 0 then
      local header_row = ""

      for _, col in ipairs(self.columns) do
        local width = self.column_widths[col] or 10

        if col == "select" then
          header_row = header_row .. "    " -- Space for checkbox
        else
          local col_name = string.upper(col)
          header_row = header_row .. col_name .. string.rep(" ", width - #col_name) .. " "
        end
      end

      table.insert(content, header_row)
    end

    -- Calculate visible items range
    local visible_start = math.max(1, self.scroll_offset + 1)
    local visible_end = math.min(#self.items, self.scroll_offset + self.height - self.header_rows - self.footer_rows)

    -- Add item rows
    for idx = visible_start, visible_end do
      local item = self.items[idx]
      local row_content = ""

      -- Format the item if formatter available
      local formatted_item = item
      if self.formatter then
        formatted_item = self.formatter(item, idx)
      end

      -- Build row based on columns
      for _, col in ipairs(self.columns) do
        local width = self.column_widths[col] or 10

        if col == "select" then
          local selected = self.multi_select and self.selected_items[idx] or idx == self.selected_index
          local checkbox = selected and "[" .. icon_set.selected .. "] " or "[" .. icon_set.unselected .. "] "
          row_content = row_content .. checkbox
        else
          local val = formatted_item[col] or ""
          if type(val) == "string" then
            row_content = row_content .. utils.clip_text(val, width) .. " "
          else
            row_content = row_content .. tostring(val) .. string.rep(" ", width - #tostring(val)) .. " "
          end
        end
      end

      table.insert(content, row_content)
    end

    -- Add footer if needed
    for _ = 1, self.footer_rows do
      table.insert(content, "")
    end

    -- Set content
    vim.api.nvim_buf_set_lines(bufnr, self.row, self.row + #content, false, content)

    -- Apply highlighting
    vim.api.nvim_buf_clear_namespace(bufnr, self.namespace, self.row, self.row + #content)

    -- Highlight header if present
    if self.header_rows > 0 then
      vim.api.nvim_buf_add_highlight(bufnr, self.namespace, "TaskforgeDialogHeader", self.row, 0, -1)
    end

    -- Highlight items
    for i = visible_start, visible_end do
      local item = self.items[i]
      local line_idx = self.row + (i - visible_start) + self.header_rows
      local line = content[line_idx - self.row + 1]

      -- Highlight checkbox
      if vim.tbl_contains(self.columns, "select") then
        local selected = self.multi_select and self.selected_items[i] or i == self.selected_index

        if line and line:sub(1, 1) == "[" then
          local hl_group = selected and "TaskforgeItemSelected" or "TaskforgeItemUnselected"
          vim.api.nvim_buf_add_highlight(bufnr, self.namespace, hl_group, line_idx, 0, 3)
        end
      end

      -- Highlight current selection
      if i == self.selected_index then
        vim.api.nvim_buf_add_highlight(bufnr, self.namespace, "TaskforgeItemFocused", line_idx, 0, -1)
      end

      -- Highlight by properties - use theme if available
      local theme = require("taskforge.ui.theme")
      theme.highlight_task_item(bufnr, line_idx, item, self.namespace)
    end

    -- Make buffer readonly if needed
    if self.dialog.buf_options and self.dialog.buf_options.modifiable == false then
      vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    end

    return self
  end

  -- Move selection up
  list.move_up = function(self)
    if self.selected_index > 1 then
      self.selected_index = self.selected_index - 1

      -- Adjust scroll if needed
      if self.selected_index <= self.scroll_offset then
        self.scroll_offset = math.max(0, self.selected_index - 1)
      end

      -- Call on_select callback if provided
      if self.on_select then
        self.on_select(self.items[self.selected_index], self.selected_index)
      end

      self:render()
    end

    return self
  end

  -- Move selection down
  list.move_down = function(self)
    if self.selected_index < #self.items then
      self.selected_index = self.selected_index + 1

      -- Adjust scroll if needed
      local visible_items = self.height - self.header_rows - self.footer_rows
      if self.selected_index >= self.scroll_offset + visible_items then
        self.scroll_offset = math.max(0, self.selected_index - visible_items + 1)
      end

      -- Call on_select callback if provided
      if self.on_select then
        self.on_select(self.items[self.selected_index], self.selected_index)
      end

      self:render()
    end

    return self
  end

  -- Toggle selection for multi-select
  list.toggle_selection = function(self)
    if self.multi_select then
      self.selected_items[self.selected_index] = not self.selected_items[self.selected_index]

      -- Call on_toggle if provided
      if self.on_toggle then
        self.on_toggle(self.items[self.selected_index], self.selected_index, self.selected_items[self.selected_index])
      end

      self:render()
    end

    return self
  end

  -- Toggle all to match current item
  list.toggle_all = function(self)
    if self.multi_select then
      local current_state = self.selected_items[self.selected_index]

      -- Toggle all to match current
      for i = 1, #self.items do
        self.selected_items[i] = not current_state
      end

      self:render()
    end

    return self
  end

  -- Submit selection
  list.submit = function(self)
    if self.on_submit then
      if self.multi_select then
        -- Collect selected items
        local selected = {}
        for i, item in ipairs(self.items) do
          if self.selected_items[i] then
            table.insert(selected, item)
          end
        end

        self.on_submit(selected)
      else
        -- Submit current item
        self.on_submit(self.items[self.selected_index])
      end
    end

    return self
  end

  -- Setup keymaps
  list.setup_keymaps = function(self)
    if not self.dialog or not self.dialog.popup then
      return self
    end

    -- Get key config
    local cfg = config.get()
    local keymaps = (cfg.interface and cfg.interface.keymaps) or {}

    -- Map up keys
    local up_keys = type(keymaps.up) == "table" and keymaps.up or { keymaps.up or "k", "<Up>" }
    for _, key in ipairs(type(up_keys) == "table" and up_keys or { up_keys }) do
      self.dialog.popup:map("n", key, function()
        self:move_up()
      end, { noremap = true })
    end

    -- Map down keys
    local down_keys = type(keymaps.down) == "table" and keymaps.down or { keymaps.down or "j", "<Down>" }
    for _, key in ipairs(type(down_keys) == "table" and down_keys or { down_keys }) do
      self.dialog.popup:map("n", key, function()
        self:move_down()
      end, { noremap = true })
    end

    -- Map select key for multi-select
    if self.multi_select then
      self.dialog.popup:map("n", keymaps.select_task or "v", function()
        self:toggle_selection()
      end, { noremap = true })

      -- Map select all key
      self.dialog.popup:map("n", keymaps.select_all_task or "V", function()
        self:toggle_all()
      end, { noremap = true })
    end

    -- Map submit key
    self.dialog.popup:map("n", keymaps.confirm or "<CR>", function()
      self:submit()
    end, { noremap = true })

    return self
  end

  -- Get currently selected item(s)
  list.get_selected = function(self)
    if self.multi_select then
      local selected = {}
      for i, item in ipairs(self.items) do
        if self.selected_items[i] then
          table.insert(selected, item)
        end
      end
      return selected
    else
      return self.items[self.selected_index]
    end
  end

  -- Update items
  list.update_items = function(self, new_items)
    self.items = new_items or {}
    self.selected_index = math.min(self.selected_index, #self.items)
    if self.selected_index < 1 and #self.items > 0 then
      self.selected_index = 1
    end

    -- Reset multi-select if needed
    if self.multi_select then
      self.selected_items = {}
    end

    self:render()
    return self
  end

  -- Set selection index
  list.set_selected_index = function(self, index)
    if index >= 1 and index <= #self.items then
      self.selected_index = index

      -- Call on_select callback if provided
      if self.on_select then
        self.on_select(self.items[self.selected_index], self.selected_index)
      end

      self:render()
    end

    return self
  end

  -- Finally, render the initial state
  list:render()

  return list
end

return M

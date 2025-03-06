-- lua/taskforge/ui/dialog.lua
--
-- Generic dialog component for Taskforge UI

local M = {}
local utils = require("taskforge.utils")
local config = require("taskforge.config")

-- Dialog component global state
M._dialogs = {}

-- Create a new dialog
-- @param options table Dialog options
-- @return table Dialog object
function M.create(options)
  -- Ensure we have nui.popup
  local has_nui, NuiPopup = pcall(require, "nui.popup")
  if not has_nui then
    utils.notify("Dialog requires nui.nvim", vim.log.levels.WARN)
    return nil
  end

  -- Set up default options
  options = vim.tbl_deep_extend("force", {
    id = "taskforge_dialog_" .. tostring(#M._dialogs + 1),
    title = "Dialog",
    mode = "dialog", -- dialog, confirm, menu, etc.
    content = {}, -- Lines of text
    popup = nil, -- NUI popup instance
    namespace = vim.api.nvim_create_namespace("taskforge_dialog_" .. tostring(#M._dialogs + 1)),

    -- Sizing
    width_percent = 50,
    height_percent = 50,
    min_width = 40,
    min_height = 10,
    max_width = nil,
    max_height = nil,

    -- Position
    position = "center", -- center, top, bottom

    -- Style
    border_style = "rounded",
    win_options = {
      cursorline = true,
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },

    -- Behaviors
    focusable = true,
    enter = true,
    close_on_done = true,
    close_on_esc = true,

    -- Events & callbacks
    on_close = nil,
    on_submit = nil,
    on_cancel = nil,
    render = nil, -- Custom render function

    -- Keymaps
    keymaps = {
      ["<Esc>"] = function(dialog)
        dialog:cancel()
      end,
      ["q"] = function(dialog)
        dialog:cancel()
      end,
    },
  }, options or {})

  -- Calculate size based on current window and percentages
  local win_width = vim.api.nvim_win_get_width(0)
  local win_height = vim.api.nvim_win_get_height(0)

  local width = math.floor(win_width * options.width_percent / 100)
  local height = math.floor(win_height * options.height_percent / 100)

  -- Apply min/max constraints
  if options.min_width then
    width = math.max(width, options.min_width)
  end
  if options.min_height then
    height = math.max(height, options.min_height)
  end
  if options.max_width then
    width = math.min(width, options.max_width)
  end
  if options.max_height then
    height = math.min(height, options.max_height)
  end

  -- Ensure dialog fits within window
  width = math.min(width, win_width - 4)
  height = math.min(height, win_height - 4)

  -- Calculate row position
  local row
  if options.position == "top" then
    row = math.floor(win_height * 0.15)
  elseif options.position == "bottom" then
    row = math.floor(win_height * 0.75) - math.floor(height / 2)
  else
    -- Default to center
    row = math.floor((win_height - height) / 2)
  end

  local col = math.floor((win_width - width) / 2)

  -- Create the dialog state
  local dialog = {
    id = options.id,
    title = options.title,
    mode = options.mode,
    content = options.content,
    namespace = options.namespace,
    keymaps = options.keymaps,
    width = width,
    height = height,
    row = row,
    col = col,
    on_close = options.on_close,
    on_submit = options.on_submit,
    on_cancel = options.on_cancel,
    render = options.render,
    close_on_done = options.close_on_done,
    close_on_esc = options.close_on_esc,
    data = {}, -- For storing arbitrary data
    _closed = false,
  }

  -- Create popup
  local popup = NuiPopup({
    enter = options.enter,
    focusable = options.focusable,
    border = {
      style = options.border_style,
      text = {
        top = " " .. options.title .. " ",
        top_align = "center",
      },
    },
    position = {
      row = row,
      col = col,
    },
    size = {
      width = width,
      height = height,
    },
    buf_options = options.buf_options,
    win_options = options.win_options,
  })

  -- Store popup reference
  dialog.popup = popup

  -- Set close handler
  popup:on("BufLeave", function()
    if not dialog._closed and dialog.close_on_esc then
      dialog:close()
    end
  end, { once = true })

  -- Set up keymaps
  for key, handler in pairs(dialog.keymaps) do
    popup:map("n", key, function()
      handler(dialog)
    end, { noremap = true })
  end

  -- Add methods

  -- Close the dialog
  dialog.close = function(self)
    if self._closed then
      return
    end

    -- Mark as closed to prevent duplicate calls
    self._closed = true

    -- Call on_close callback if provided
    if self.on_close then
      self.on_close(self)
    end

    -- Unmount the popup
    if self.popup then
      self.popup:unmount()
    end

    -- Remove from active dialogs
    for i, d in ipairs(M._dialogs) do
      if d.id == self.id then
        table.remove(M._dialogs, i)
        break
      end
    end
  end

  -- Submit/apply the dialog
  dialog.submit = function(self, result)
    -- Call on_submit callback if provided
    if self.on_submit then
      self.on_submit(self, result)
    end

    -- Close if configured to do so
    if self.close_on_done then
      self:close()
    end
  end

  -- Cancel the dialog
  dialog.cancel = function(self)
    -- Call on_cancel callback if provided
    if self.on_cancel then
      self.on_cancel(self)
    end

    -- Close dialog
    self:close()
  end

  -- Get value of content
  dialog.get_content = function(self)
    if not self.popup or not self.popup.bufnr then
      return {}
    end

    return vim.api.nvim_buf_get_lines(self.popup.bufnr, 0, -1, false)
  end

  -- Set content
  dialog.set_content = function(self, content)
    if not self.popup or not self.popup.bufnr then
      return
    end

    -- Save content
    self.content = content

    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(self.popup.bufnr, "modifiable", true)

    -- Set lines
    vim.api.nvim_buf_set_lines(self.popup.bufnr, 0, -1, false, content)

    -- Restore readonly
    if options.buf_options and options.buf_options.modifiable == false then
      vim.api.nvim_buf_set_option(self.popup.bufnr, "modifiable", false)
    end

    return self
  end

  -- Mount the dialog
  dialog.mount = function(self)
    if not self.popup then
      return self
    end

    self.popup:mount()

    -- Set initial content
    if self.content and #self.content > 0 then
      self:set_content(self.content)
    end

    -- Call render function if provided
    if self.render then
      self:render()
    end

    return self
  end

  -- Add to active dialogs
  table.insert(M._dialogs, dialog)

  -- Mount the dialog and return
  dialog:mount()

  -- Ensure focus on newly created dialog - use vim.schedule to make sure the window is ready
  if options.enter then
    vim.schedule(function()
      if dialog.popup and dialog.popup.winid and vim.api.nvim_win_is_valid(dialog.popup.winid) then
        -- Use the nui_popup API directly to avoid issues with BufLeave
        dialog.popup:on({ "BufLeave" }, function()
          -- ignore this event for now
        end, { once = true })

        -- Force focus
        vim.api.nvim_set_current_win(dialog.popup.winid)
      end
    end)
  end

  return dialog
end

-- Show a confirmation dialog
-- @param message string Message to display
-- @param options table Dialog options
-- @param callback function Callback function(result, dialog)
-- @return table Dialog object
function M.confirm(message, options, callback)
  options = options or {}

  -- Set up options for confirmation dialog
  local confirm_options = vim.tbl_deep_extend("force", {
    title = options.title or "Confirm",
    mode = "confirm",
    content = type(message) == "string" and vim.split(message, "\n") or message,
    width_percent = 40,
    height_percent = 30,
    buttons = options.buttons or { { label = "Yes", result = true }, { label = "No", result = false } },
    on_submit = function(dialog, result)
      if callback then
        callback(result, dialog)
      end
    end,
    on_cancel = function(dialog)
      if callback then
        callback(false, dialog)
      end
    end,
  }, options)

  -- Custom render function for confirmation dialog
  confirm_options.render = function(self)
    if not self.popup or not self.popup.bufnr then
      return self
    end

    local bufnr = self.popup.bufnr

    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

    -- Clear buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

    -- Add message lines
    local lines = vim.tbl_map(function(line)
      return type(line) == "string" and line or tostring(line)
    end, self.content)

    -- Add blank line after message
    table.insert(lines, "")

    -- Add buttons
    local buttons_line = ""
    for i, button in ipairs(self.buttons) do
      buttons_line = buttons_line .. (i > 1 and "  " or "") .. "[ " .. button.label .. " ]"
    end

    -- Center buttons
    local centered_buttons = string.rep(" ", math.floor((self.width - #buttons_line) / 2)) .. buttons_line
    table.insert(lines, centered_buttons)

    -- Set content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    -- Add button mappings
    for i, button in ipairs(self.buttons) do
      local first_letter = button.label:sub(1, 1):lower()

      -- Map first letter of button label
      self.popup:map("n", first_letter, function()
        self:submit(button.result)
      end, { noremap = true })

      -- Map uppercase first letter too
      self.popup:map("n", first_letter:upper(), function()
        self:submit(button.result)
      end, { noremap = true })

      -- Highlight button text
      local line_idx = #lines - 1
      local button_start = centered_buttons:find("%[%s" .. vim.pesc(button.label) .. "%s%]")
      if button_start then
        vim.api.nvim_buf_add_highlight(
          bufnr,
          self.namespace,
          "Special",
          line_idx,
          button_start - 1,
          button_start + #button.label + 3 - 1
        )
      end
    end

    -- Set buffer as unmodifiable if readonly
    if self.buf_options and self.buf_options.modifiable == false then
      vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    end

    return self
  end

  -- Add keymaps for buttons
  for i, button in ipairs(confirm_options.buttons) do
    local first_letter = button.label:sub(1, 1):lower()
    confirm_options.keymaps[first_letter] = function(dialog)
      dialog:submit(button.result)
    end
    confirm_options.keymaps[first_letter:upper()] = function(dialog)
      dialog:submit(button.result)
    end
  end

  -- Create and return dialog
  return M.create(confirm_options)
end

-- Show an input dialog
-- @param prompt string Prompt message
-- @param options table Dialog options
-- @param callback function Callback function(result, dialog)
-- @return table Dialog object
function M.input(prompt, options, callback)
  options = options or {}

  -- Set up options for input dialog
  local input_options = vim.tbl_deep_extend("force", {
    title = options.title or "Input",
    mode = "input",
    content = type(prompt) == "string" and vim.split(prompt, "\n") or prompt,
    width_percent = 50,
    height_percent = 20,
    default = options.default or "",
    on_submit = function(dialog, result)
      if callback then
        callback(result, dialog)
      end
    end,
    on_cancel = function(dialog)
      if callback then
        callback(nil, dialog)
      end
    end,
  }, options)

  -- Custom render function for input dialog
  input_options.render = function(self)
    if not self.popup or not self.popup.bufnr then
      return self
    end

    local bufnr = self.popup.bufnr

    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

    -- Clear buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

    -- Add prompt lines
    local lines = vim.tbl_map(function(line)
      return type(line) == "string" and line or tostring(line)
    end, self.content)

    -- Add blank line after prompt
    table.insert(lines, "")

    -- Add input line with default value
    table.insert(lines, self.default or "")

    -- Set content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    -- Position cursor on input line
    vim.api.nvim_win_set_cursor(self.popup.winid, { #lines, 0 })

    -- Set up submit mapping
    self.popup:map("i", "<CR>", function()
      -- Get current input value
      local input_line = vim.api.nvim_buf_get_lines(bufnr, #lines - 1, #lines, false)[1]
      self:submit(input_line)
    end, { noremap = true })

    -- Start in insert mode
    vim.cmd("startinsert!")

    return self
  end

  -- Make Enter submit the dialog in normal mode too
  input_options.keymaps["<CR>"] = function(dialog)
    local content = dialog:get_content()
    local result = content[#content]
    dialog:submit(result)
  end

  -- Create and return dialog
  return M.create(input_options)
end

-- Get the active dialog by ID
-- @param id string Dialog ID
-- @return table|nil Dialog object
function M.get(id)
  for _, dialog in ipairs(M._dialogs) do
    if dialog.id == id then
      return dialog
    end
  end
  return nil
end

-- Close all active dialogs
function M.close_all()
  -- Create a copy to avoid modification during iteration
  local dialogs = vim.deepcopy(M._dialogs)
  for _, dialog in ipairs(dialogs) do
    dialog:close()
  end

  -- Clear dialogs table
  M._dialogs = {}
end

return M

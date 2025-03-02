-- lua/taskforge/tracker/ui.lua
--
-- UI components for tag interaction including batch processing

local M = {}
local utils = require("taskforge.utils")
local core = require("taskforge.tracker.core")
local config = require("taskforge.config")

-- Namespace for batch tag processing
local batch = {
  active = false,
  candidates = {},
  selected_index = 1,
  visible = false,
  bufnr = nil,
  highlight_namespace = nil,
  namespace = nil,
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
local function calculate_ui_size()
  local cfg = config.get().interface and config.get().interface.batch_ui or {}

  -- Get current window dimensions
  local win_width = vim.api.nvim_win_get_width(0)
  local win_height = vim.api.nvim_win_get_height(0)

  -- Calculate dimensions based on percentages
  local width_percent = cfg.width_percent or 80
  local height_percent = cfg.height_percent or 20

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

-- Extract tag description for display
local function get_tag_description(bufnr, candidate)
  local lang = require("taskforge.lang").get_for_buffer(bufnr)
  local comment_text = vim.treesitter.get_node_text(candidate.node, bufnr)
  local info = lang.extract_tag_info(comment_text, candidate.tag)

  return info and info.description or "No description"
end

-- Jump to line containing a tag
function M.jump_to_tag(bufnr, lnum)
  -- Get current window
  local win = vim.api.nvim_get_current_win()

  -- Only jump in main buffer if UI is active
  if batch.active and vim.api.nvim_buf_is_valid(bufnr) then
    -- Find a window containing our target buffer
    local target_win = nil
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == bufnr then
        target_win = w
        break
      end
    end

    if target_win then
      -- Set cursor to tag line - don't change windows
      local topline = vim.fn.line("w0", target_win)
      local botline = vim.fn.line("w$", target_win)

      -- Check if line is out of view
      if lnum + 1 < topline or lnum + 1 > botline then
        -- Need to adjust view
        vim.api.nvim_win_set_cursor(target_win, { lnum + 1, 0 })

        -- Center the view
        vim.api.nvim_command(
          "call winrestview({'lnum': " .. (lnum + 1) .. ", 'topline': " .. math.max(1, lnum - 5) .. "})"
        )
        vim.api.nvim_command("normal! zz")
      end

      -- Highlight the line even if not changing windows
      if not batch.highlight_namespace then
        batch.highlight_namespace = vim.api.nvim_create_namespace("taskforge_tag_highlight")
      end
      vim.api.nvim_buf_clear_namespace(bufnr, batch.highlight_namespace, 0, -1)
      vim.api.nvim_buf_add_highlight(bufnr, batch.highlight_namespace, "Visual", lnum, 0, -1)

      -- Return focus to UI
      local ui_winid = nil
      if ui_components.popup and ui_components.popup.winid then
        ui_winid = ui_components.popup.winid
        if vim.api.nvim_win_is_valid(ui_winid) then
          vim.api.nvim_set_current_win(ui_winid)
        end
      end
    end
  end
end

-- Process a tag candidate with auto-create config
local function process_auto_tag(bufnr, candidate)
  local tags = require("taskforge.tracker.tags")
  tags.process_tag(bufnr, candidate.lnum, candidate.tag, candidate.def, candidate.node, false) -- false = allow task creation
end

-- Process all selected tags from batch interface
function M.apply_selections()
  if not batch.active then
    return
  end

  -- Process selected tags
  local processed = 0
  local optout = 0

  for _, item in ipairs(batch.candidates) do
    if item.selected then
      -- Create task
      local tags = require("taskforge.tracker.tags")
      tags.process_tag(batch.bufnr, item.lnum, item.tag, item.def, item.node, false)
      processed = processed + 1
    else
      -- Add opt-out marker
      local tags = require("taskforge.tracker.tags")
      tags.add_optout_marker(batch.bufnr, item.lnum)
      optout = optout + 1
    end
  end

  -- Close UI
  M.close_batch_ui()

  -- Notify results
  if processed > 0 or optout > 0 then
    local msg = string.format("Processed %d tags, marked %d tags as [notrack]", processed, optout)
    utils.notify(msg)
  end
end

-- Create help popup
function M.show_help_popup()
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

  -- Create help content with dynamic keys
  local help_text = {
    "Taskforge Tag Processing Help",
    "==========================",
    "",
    "Navigation:",
    "  " .. format_keymap(keymaps.up or { "k", "<Up>" }) .. "  : Move up",
    "  " .. format_keymap(keymaps.down or { "j", "<Down>" }) .. "  : Move down",
    "",
    "Actions:",
    "  " .. format_keymap(keymaps.select_task or "v") .. "  : Toggle selected tag",
    "  " .. format_keymap(keymaps.select_all_task or "V") .. "  : Toggle all tags to match current",
    "  " .. format_keymap(keymaps.quit or "q") .. "  : Apply selections and exit",
    "  " .. format_keymap(keymaps.unselect or "<esc>") .. "  : Cancel and exit",
    "  " .. format_keymap(keymaps.help or "?") .. "  : Show this help",
    "",
    "Press any key to close",
  }

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

-- Process tag candidates in batch
function M.batch_process_tags(bufnr, candidates)
  -- Debug log the candidates
  utils.notify("Processing " .. #candidates .. " tag candidates", vim.log.levels.INFO)

  -- Group candidates by creation mode
  local auto_create = {}
  local interactive_tags = {}

  for _, candidate in ipairs(candidates) do
    -- Debug the candidate
    utils.debug_log("UI", "Candidate tag", {
      tag = candidate.tag,
      lnum = candidate.lnum,
      create = candidate.def and candidate.def.create or "unknown",
    })

    if candidate.def and candidate.def.create == "auto" then
      table.insert(auto_create, candidate)
    else
      -- Get description
      local desc = get_tag_description(bufnr, candidate)
      utils.debug_log("UI", "Tag description", desc)

      -- Create interactive tag entry
      table.insert(interactive_tags, {
        lnum = candidate.lnum,
        tag = candidate.tag,
        def = candidate.def,
        node = candidate.node,
        description = desc,
        selected = candidate.def and candidate.def.create == "ask", -- Pre-select "ask" tags
      })
    end
  end

  -- Process auto-create tags silently
  for _, candidate in ipairs(auto_create) do
    process_auto_tag(bufnr, candidate)
  end

  -- Show UI for interactive tags if any exist
  if #interactive_tags > 0 then
    utils.notify("Found " .. #interactive_tags .. " tags requiring user decision", vim.log.levels.INFO)
    batch.candidates = interactive_tags
    batch.bufnr = bufnr
    M.show_batch_ui(bufnr)
  elseif #auto_create > 0 then
    utils.notify(string.format("Processed %d tags automatically", #auto_create))
  else
    utils.notify("No tags found to process")
  end
end

-- Show batch UI for tag processing
function M.show_batch_ui(bufnr)
  -- Ensure we have NUI
  local has_nui, NuiPopup = pcall(require, "nui.popup")
  if not has_nui then
    utils.notify("Batch UI requires nui.nvim", vim.log.levels.WARN)
    -- Fall back to simple selection
    M.show_simple_selection(bufnr, batch.candidates)
    return
  end

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

  -- Format keys for display (handle special keys)
  local display_quit = key_quit:gsub("<", "\\<")
  local display_cancel = key_cancel:gsub("<Esc>", "Esc"):gsub("<", "\\<")
  local display_help = key_help:gsub("<", "\\<")

  -- Calculate size and position for top third
  local win_width = vim.api.nvim_win_get_width(0)
  local win_height = vim.api.nvim_win_get_height(0)

  local width = math.min(70, win_width - 10)
  local height = math.min(10, #batch.candidates + 4)

  -- Position in top third
  local row = math.floor(win_height * 0.15)
  local col = math.floor((win_width - width) / 2)

  -- Create popup with dynamic key display
  local popup = NuiPopup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = " Task Tags ",
        top_align = "center",
        bottom = string.format(" %s: Apply | %s: Cancel | %s: Help ", display_quit, display_cancel, display_help),
        bottom_align = "center",
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

  -- Set content with simple approach
  local content = {}
  table.insert(content, "Select which tags to create tasks for:")
  table.insert(content, "")

  for i, item in ipairs(batch.candidates) do
    local marker = "[ ] "
    if item.selected then
      marker = "[x] "
    end

    table.insert(
      content,
      string.format(
        "%s%s: %s (line %d)",
        marker,
        item.tag,
        item.description:sub(1, 40) .. (string.len(item.description) > 40 and "..." or ""),
        item.lnum + 1
      )
    )
  end

  -- Set lines directly
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, content)

  -- Add highlighting
  vim.api.nvim_buf_add_highlight(popup.bufnr, -1, "Title", 0, 0, -1)

  for i = 3, #content do
    local line_idx = i - 1
    -- Highlight checkboxes
    if content[i]:sub(1, 3) == "[x]" then
      vim.api.nvim_buf_add_highlight(popup.bufnr, batch.namespace, "DiagnosticOk", line_idx, 0, 3)
    else
      vim.api.nvim_buf_add_highlight(popup.bufnr, batch.namespace, "DiagnosticError", line_idx, 0, 3)
    end

    -- Highlight tag
    local tag_end = content[i]:find(":", 4) or 10
    vim.api.nvim_buf_add_highlight(popup.bufnr, batch.namespace, "Type", line_idx, 4, tag_end)
  end

  -- Force cursor to first item row and focus window
  vim.defer_fn(function()
    if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      vim.api.nvim_set_current_win(popup.winid)
      vim.api.nvim_win_set_cursor(popup.winid, { 3, 0 })

      -- Jump to first tag in source
      if #batch.candidates > 0 then
        M.jump_to_tag(bufnr, batch.candidates[1].lnum)
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

        -- Jump to tag in source
        local item_idx = row - 3 -- after moving up
        if item_idx >= 1 and item_idx <= #batch.candidates then
          M.jump_to_tag(bufnr, batch.candidates[item_idx].lnum)
        end
      end
    end, opts)
  end

  -- Movement: down
  for _, key in ipairs(type(down_keys) == "table" and down_keys or { down_keys }) do
    popup:map("n", key, function()
      local cursor = vim.api.nvim_win_get_cursor(popup.winid)
      local row = cursor[1]
      -- Don't go past the last item or above first item
      if row < #content then
        vim.api.nvim_win_set_cursor(popup.winid, { row + 1, 0 })

        -- Jump to tag in source
        local item_idx = row - 3 + 2 -- after moving down
        if item_idx >= 1 and item_idx <= #batch.candidates then
          M.jump_to_tag(bufnr, batch.candidates[item_idx].lnum)
        end
      end
    end, opts)
  end

  -- Toggle item: use select_task key
  popup:map("n", key_select, function()
    local cursor = vim.api.nvim_win_get_cursor(popup.winid)
    local row = cursor[1]

    -- Only toggle item rows, not headers
    if row >= 3 and row - 3 < #batch.candidates then
      local item_idx = row - 3 + 1

      -- Toggle selection
      batch.candidates[item_idx].selected = not batch.candidates[item_idx].selected

      -- Update display
      local line = vim.api.nvim_buf_get_lines(popup.bufnr, row - 1, row, false)[1]
      local new_line

      if batch.candidates[item_idx].selected then
        new_line = line:gsub("^%[ %]", "[x]")
        vim.api.nvim_buf_clear_namespace(popup.bufnr, batch.namespace, row - 1, row)
        vim.api.nvim_buf_add_highlight(popup.bufnr, batch.namespace, "DiagnosticOk", row - 1, 0, 3)
      else
        new_line = line:gsub("^%[x%]", "[ ]")
        vim.api.nvim_buf_clear_namespace(popup.bufnr, batch.namespace, row - 1, row)
        vim.api.nvim_buf_add_highlight(popup.bufnr, batch.namespace, "DiagnosticError", row - 1, 0, 3)
      end

      vim.api.nvim_buf_set_lines(popup.bufnr, row - 1, row, false, { new_line })

      -- Restore tag highlighting
      local tag_end = new_line:find(":", 4) or 10
      vim.api.nvim_buf_add_highlight(popup.bufnr, batch.namespace, "Type", row - 1, 4, tag_end)
    end
  end, opts)

  -- Toggle all: use select_all_task key
  popup:map("n", key_select_all, function()
    local cursor = vim.api.nvim_win_get_cursor(popup.winid)
    local row = cursor[1]

    -- Only toggle if on an item row
    if row >= 3 and row - 3 < #batch.candidates then
      local item_idx = row - 3 + 1
      local new_state = not batch.candidates[item_idx].selected

      -- Set all to match
      for i = 1, #batch.candidates do
        batch.candidates[i].selected = new_state
      end

      -- Update display
      M.show_batch_ui(bufnr)
    end
  end, opts)

  -- Apply and exit: use quit key
  popup:map("n", key_quit, function()
    M.apply_selections()
  end, opts)

  -- Cancel and exit: use unselect key
  popup:map("n", key_cancel, function()
    M.cancel_batch_processing()
  end, opts)

  -- Help: use help key
  popup:map("n", key_help, function()
    M.show_help_popup()
  end, opts)

  -- Jump to tag on Enter
  popup:map("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(popup.winid)
    local row = cursor[1]

    -- Only jump if on an item row
    if row >= 3 and row - 3 < #batch.candidates then
      local item_idx = row - 3 + 1
      M.jump_to_tag(bufnr, batch.candidates[item_idx].lnum)
    end
  end, opts)

  -- Set active flag
  batch.active = true
  batch.visible = true

  return popup
end

-- Cancel batch processing
function M.cancel_batch_processing()
  utils.notify("Cancelling batch processing")

  -- Just close the UI without processing
  M.close_batch_ui()

  -- Notify user
  utils.notify("Tag processing cancelled")
end

-- Close batch UI
function M.close_batch_ui()
  utils.notify("Closing batch UI")

  -- Clear highlight in buffer
  if batch.highlight_namespace and batch.bufnr then
    pcall(vim.api.nvim_buf_clear_namespace, batch.bufnr, batch.highlight_namespace, 0, -1)
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
  batch.selected_index = 1

  utils.notify("Batch UI closed")
end

-- Simple selection UI fallback for when NUI is not available
function M.show_simple_selection(bufnr, candidates)
  if #candidates == 0 then
    utils.notify("No tags found to process")
    return
  end

  -- Format items for selection
  local items = {}
  for i, candidate in ipairs(candidates) do
    local selected = candidate.def.create == "ask"
    table.insert(items, {
      text = string.format(
        "[%s] %s: %s (line %d)",
        selected and "✓" or "✗",
        candidate.tag,
        candidate.description:sub(1, 40) .. (candidate.description:len() > 40 and "..." or ""),
        candidate.lnum + 1
      ),
      index = i,
      candidate = candidate,
      selected = selected,
    })
  end

  vim.ui.select(items, {
    prompt = "Select tags to create tasks for:",
    format_item = function(item)
      return item.text
    end,
  }, function(selected)
    if selected then
      -- Jump to the selected tag
      vim.api.nvim_win_set_cursor(0, { selected.candidate.lnum + 1, 0 })

      -- Ask for confirmation
      utils.confirm_yesno(
        "Create task for: " .. selected.candidate.tag .. ": " .. selected.candidate.description .. "?",
        function(choice)
          if choice == 1 then -- Yes
            -- Process this tag
            process_auto_tag(bufnr, selected.candidate)

            -- Show the next candidate
            table.remove(candidates, selected.index)
            if #candidates > 0 then
              vim.defer_fn(function()
                M.show_simple_selection(bufnr, candidates)
              end, 100)
            end
          else
            -- Skip to next or mark as optout
            utils.confirm_yesno("Add [notrack] marker to prevent future prompts?", function(choice2)
              if choice2 == 1 then
                -- Add opt-out marker
                local tags = require("taskforge.tracker.tags")
                tags.add_optout_marker(bufnr, selected.candidate.lnum)
              end

              -- Show the next candidate
              table.remove(candidates, selected.index)
              if #candidates > 0 then
                vim.defer_fn(function()
                  M.show_simple_selection(bufnr, candidates)
                end, 10)
              end
            end)
          end
        end
      )
    end
  end)
end

-- Navigate between tags in a buffer
function M.navigate_tags_in_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Get all tags in the buffer
  local tags = {}
  local cached_tags = core.get_all_cached_tags(bufnr)

  if not cached_tags or vim.tbl_isempty(cached_tags) then
    utils.notify("No tags found in buffer", vim.log.levels.INFO)
    return
  end

  -- Convert to list and sort by line number
  for lnum, tag_data in pairs(cached_tags) do
    table.insert(tags, {
      lnum = lnum,
      text = tag_data.text,
      tag_name = tag_data.tag_name,
      uuid = tag_data.uuid,
    })
  end

  table.sort(tags, function(a, b)
    return a.lnum < b.lnum
  end)

  -- Set up state for navigation
  local state = {
    current_index = 1,
    tags = tags,
  }

  -- Store state in buffer variable
  vim.api.nvim_buf_set_var(bufnr, "taskforge_nav_state", state)

  -- Set up keymaps
  M._setup_navigation_keymaps(bufnr)

  -- Move to first tag
  M._goto_tag(bufnr, 1)

  -- Show help
  utils.notify("Tag navigation active. Use n/p to move between tags, ESC to exit", vim.log.levels.INFO)
end

-- Set up keymaps for tag navigation
function M._setup_navigation_keymaps(bufnr)
  local opts = { buffer = bufnr, noremap = true, silent = true }

  -- Next tag
  vim.api.nvim_buf_set_keymap(bufnr, "n", "n", [[<cmd>lua require('taskforge.tracker.ui')._goto_next_tag()<CR>]], opts)

  -- Previous tag
  vim.api.nvim_buf_set_keymap(bufnr, "n", "p", [[<cmd>lua require('taskforge.tracker.ui')._goto_prev_tag()<CR>]], opts)

  -- Exit navigation
  vim.api.nvim_buf_set_keymap(
    bufnr,
    "n",
    "<Esc>",
    [[<cmd>lua require('taskforge.tracker.ui')._exit_tag_nav()<CR>]],
    opts
  )
end

-- Go to next tag
function M._goto_next_tag()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, state = pcall(vim.api.nvim_buf_get_var, bufnr, "taskforge_nav_state")

  if ok and state then
    local new_index = state.current_index + 1
    if new_index > #state.tags then
      new_index = 1 -- Wrap around
    end

    M._goto_tag(bufnr, new_index)
  end
end

-- Go to previous tag
function M._goto_prev_tag()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, state = pcall(vim.api.nvim_buf_get_var, bufnr, "taskforge_nav_state")

  if ok and state then
    local new_index = state.current_index - 1
    if new_index < 1 then
      new_index = #state.tags -- Wrap around
    end

    M._goto_tag(bufnr, new_index)
  end
end

-- Go to specific tag by index
function M._goto_tag(bufnr, index)
  local ok, state = pcall(vim.api.nvim_buf_get_var, bufnr, "taskforge_nav_state")

  if ok and state and index <= #state.tags then
    -- Update current index
    state.current_index = index
    vim.api.nvim_buf_set_var(bufnr, "taskforge_nav_state", state)

    -- Get tag info
    local tag = state.tags[index]

    -- Move cursor to tag
    vim.api.nvim_win_set_cursor(0, { tag.lnum + 1, 0 })
    vim.cmd("normal! zz") -- Center view

    -- Show info in command line
    local info =
      string.format("Tag %d/%d: %s", index, #state.tags, tag.text:sub(1, 50) .. (tag.text:len() > 50 and "..." or ""))

    vim.api.nvim_echo({ { info, "SpecialChar" } }, false, {})
  end
end

-- Exit tag navigation mode
function M._exit_tag_nav()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Remove keymaps
  pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", "n")
  pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", "p")
  pcall(vim.api.nvim_buf_del_keymap, bufnr, "n", "<Esc>")

  -- Remove state
  pcall(vim.api.nvim_buf_del_var, bufnr, "taskforge_nav_state")

  utils.notify("Tag navigation ended", vim.log.levels.INFO)
end

-- Show info about a tag
function M.show_tag_info(bufnr, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  lnum = lnum or (vim.api.nvim_win_get_cursor(0)[1] - 1)

  -- Get tag info from cache
  local tag_data = core.get_cached_tag(bufnr, lnum)
  if not tag_data then
    utils.notify("No tag found at cursor position", vim.log.levels.WARN)
    return
  end

  -- Check if tag has a UUID
  if tag_data.uuid then
    -- Get task details
    local tasks = require("taskforge.tasks")
    local task = tasks.get_task(tag_data.uuid)

    if task then
      -- Show task info in a popup
      M._show_task_popup(task)
    else
      utils.notify("Task not found for UUID: " .. tag_data.uuid, vim.log.levels.WARN)
    end
  else
    -- Just show tag info
    local info =
      string.format("Tag: %s\nLine: %d\nNot tracked in taskwarrior", tag_data.tag_name or "Unknown", lnum + 1)

    utils.notify(info, vim.log.levels.INFO)
  end
end

-- Show task info in a popup
function M._show_task_popup(task)
  local has_nui, nui = pcall(require, "nui")

  if has_nui then
    -- Use Nui popup
    local Popup = require("nui.popup")
    local event = require("nui.utils.autocmd").event

    -- Format task details
    local content = {
      "Task: " .. task.description,
      "UUID: " .. task.uuid,
      "Status: " .. task.status,
    }

    if task.project then
      table.insert(content, "Project: " .. task.project)
    end

    if task.priority then
      table.insert(content, "Priority: " .. task.priority)
    end

    if task.tags and #task.tags > 0 then
      table.insert(content, "Tags: " .. table.concat(task.tags, ", "))
    end

    if task.due then
      table.insert(content, "Due: " .. task.due)
    end

    if task.urgency then
      table.insert(content, "Urgency: " .. string.format("%.2f", task.urgency))
    end

    -- Create popup
    local popup = Popup({
      enter = false,
      focusable = true,
      border = {
        style = "rounded",
        text = {
          top = " Task Details ",
          top_align = "center",
        },
      },
      position = "50%",
      size = {
        width = 60,
        height = #content + 2,
      },
      buf_options = {
        modifiable = false,
        readonly = true,
      },
    })

    -- Mount popup
    popup:mount()

    -- Set content
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, content)

    -- Close on events
    popup:on(event.BufLeave, function()
      popup:unmount()
    end)

    -- Close on key
    popup:map("n", "q", function()
      popup:unmount()
    end, { noremap = true })

    popup:map("n", "<Esc>", function()
      popup:unmount()
    end, { noremap = true })
  else
    -- Fallback to notification
    local info = string.format("Task: %s\nStatus: %s\nUUID: %s", task.description, task.status, task.uuid)

    utils.notify(info, vim.log.levels.INFO)
  end
end

-- Add emergency exit command
function M.setup_emergency_exit()
  vim.api.nvim_create_user_command("TaskforgeUIClose", function()
    if ui_components.popup then
      pcall(function()
        ui_components.popup:unmount()
      end)
      ui_components.popup = nil
    end

    -- Reset batch state
    batch.active = false
    batch.visible = false

    -- Clear any highlights
    if batch.highlight_namespace and batch.bufnr then
      pcall(vim.api.nvim_buf_clear_namespace, batch.bufnr, batch.highlight_namespace, 0, -1)
    end

    -- Notify
    require("taskforge.utils").notify("UI forcibly closed")
  end, {})
end

return M

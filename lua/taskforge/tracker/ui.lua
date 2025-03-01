-- lua/taskforge/tracker/ui.lua
-- UI components for tag interaction

local M = {}
local utils = require("taskforge.utils")
local core = require("taskforge.tracker.core")
local config = require("taskforge.config")

-- Process batch of tags that need user confirmation
function M.batch_process_tags(bufnr, candidates)
  if #candidates == 0 then
    return
  end

  -- Format items for selection UI
  local items = {}
  for i, candidate in ipairs(candidates) do
    -- Extract description
    local desc = M._extract_description(bufnr, candidate)

    table.insert(items, {
      text = string.format("[%s] %s (line %d)", candidate.tag, desc, candidate.lnum + 1),
      index = i,
      candidate = candidate,
      selected = false, -- Not selected by default
    })
  end

  -- Show initial dialog with options
  M._show_batch_options_dialog(bufnr, items)
end

-- Extract description from a tag candidate
function M._extract_description(bufnr, candidate)
  local lang = require("taskforge.lang").get_for_buffer(bufnr)
  local comment_text = vim.treesitter.get_node_text(candidate.node, bufnr)
  local info = lang.extract_tag_info(comment_text, candidate.tag)

  return info and info.description or "No description"
end

-- Show dialog with batch processing options
function M._show_batch_options_dialog(bufnr, items)
  -- Show a single dialog for all tags
  vim.ui.select({ "Process all tags", "Process selected tags", "Skip all tags" }, {
    prompt = string.format(
      "Found %d untracked %s. How would you like to proceed?",
      #items,
      #items == 1 and "tag" or "tags"
    ),
  }, function(choice)
    if choice == "Process all tags" then
      -- Process all tags automatically
      M._process_all_tags(bufnr, items)
    elseif choice == "Process selected tags" then
      -- Show tag selection UI
      M._show_tag_selection_ui(bufnr, items)
    else
      -- Skip processing
      utils.notify("Skipped processing tags. Use :TaskforgeTag process to process them later.")
    end
  end)
end

-- Process all tags automatically
function M._process_all_tags(bufnr, items)
  local tags = require("taskforge.tracker.tags")
  local processed = 0

  -- Process each tag
  for _, item in ipairs(items) do
    local candidate = item.candidate
    tags.process_tag(bufnr, candidate.lnum, candidate.tag, candidate.def, candidate.node, false)
    processed = processed + 1
  end

  utils.notify("Created tasks for " .. processed .. " tags")
end

-- Show tag selection UI
function M._show_tag_selection_ui(bufnr, items)
  -- Create checklist items
  local checklist_items = {}
  for i, item in ipairs(items) do
    table.insert(checklist_items, {
      text = item.text,
      checked = false,
      index = i,
    })
  end

  -- Use Nui if available, otherwise fallback to simpler UI
  local has_nui, nui = pcall(require, "nui")

  if has_nui then
    M._show_nui_checklist(bufnr, items, checklist_items)
  else
    M._show_simple_selection(bufnr, items)
  end
end

-- Show simple selection UI (fallback)
function M._show_simple_selection(bufnr, items)
  vim.ui.select(items, {
    prompt = "Select a tag to create a task for:",
    format_item = function(item)
      return item.text
    end,
  }, function(selected)
    if selected then
      -- Jump to the selected tag
      vim.api.nvim_win_set_cursor(0, { selected.candidate.lnum + 1, 0 })

      -- Process the selected tag
      M._process_single_tag(bufnr, selected.candidate)

      -- Offer to select another tag
      table.remove(items, selected.index)
      if #items > 0 then
        vim.defer_fn(function()
          M._show_simple_selection(bufnr, items)
        end, 100)
      end
    end
  end)
end

-- Show Nui-based checklist UI
function M._show_nui_checklist(bufnr, items, checklist_items)
  local Popup = require("nui.popup")
  local Menu = require("nui.menu")
  local event = require("nui.utils.autocmd").event

  local width = 80
  local height = math.min(#items + 4, 20) -- Max 20 lines height

  local menu_items = {}
  -- Add tag items
  for i, item in ipairs(checklist_items) do
    table.insert(
      menu_items,
      Menu.item(item.text, {
        checked = item.checked,
        index = item.index,
        candidate = items[item.index].candidate,
      })
    )
  end

  -- Add buttons
  table.insert(menu_items, Menu.separator("─"))
  table.insert(menu_items, Menu.item("Create tasks for selected tags", { id = "create" }))
  table.insert(menu_items, Menu.item("Skip all", { id = "skip" }))

  -- Create the menu
  local menu = Menu({
    position = "50%",
    size = {
      width = width,
      height = height,
    },
    border = {
      style = "rounded",
      text = {
        top = " Select Tags to Create Tasks ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:SpecialChar",
    },
  }, {
    lines = menu_items,
    max_width = width - 4,
    keymap = {
      focus_next = { "j", "<Down>", "<Tab>" },
      focus_prev = { "k", "<Up>", "<S-Tab>" },
      close = { "<Esc>", "<C-c>" },
      submit = { "<CR>", "<Space>" },
    },
    on_submit = function(item)
      if item.id == "create" then
        -- Process selected tags
        local selected_tags = {}
        for _, tag_item in ipairs(menu_items) do
          if tag_item.checked and tag_item.candidate then
            table.insert(selected_tags, tag_item.candidate)
          end
        end

        M._process_selected_tags(bufnr, selected_tags)
      elseif item.id == "skip" then
        -- Skip all
        utils.notify("Skipped processing tags")
      elseif item.candidate then
        -- Toggle checkbox
        item.checked = not item.checked
        menu:update_item(item, item)
      end
    end,
    on_change = function(item, _)
      if item.candidate then
        -- Toggle checkbox
        item.checked = not item.checked
        menu:update_item(item, item)
      end
    end,
  })

  -- Mount the menu
  menu:mount()

  -- Close menu when window loses focus
  menu:on(event.BufLeave, menu.menu_props.on_close, { once = true })
end

-- Process selected tags
function M._process_selected_tags(bufnr, selected_tags)
  local tags = require("taskforge.tracker.tags")
  local processed = 0

  for _, candidate in ipairs(selected_tags) do
    tags.process_tag(bufnr, candidate.lnum, candidate.tag, candidate.def, candidate.node, false)
    processed = processed + 1
  end

  if processed > 0 then
    utils.notify("Created tasks for " .. processed .. " selected tags")
  else
    utils.notify("No tags selected for processing")
  end
end

-- Process a single tag
function M._process_single_tag(bufnr, candidate)
  local tags = require("taskforge.tracker.tags")

  -- Ask for confirmation
  utils.confirm_yesno("Create task for: " .. candidate.tag .. "?", function(choice)
    if choice == 1 then -- Yes
      tags.process_tag(bufnr, candidate.lnum, candidate.tag, candidate.def, candidate.node, false)
    else
      -- User declined, offer to add opt-out marker
      utils.confirm_yesno("Add [notrack] marker to prevent future prompts?", function(choice2)
        if choice2 == 1 then
          -- Add opt-out marker
          tags.add_optout_marker(bufnr, candidate.lnum)
        end
      end)
    end
  end)
end

-- Navigate between tags in a buffer
function M.navigate_tags(bufnr)
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

return M

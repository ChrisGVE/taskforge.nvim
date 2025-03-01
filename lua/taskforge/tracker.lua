-- lua/taskforge/tracker.lua
-- Enhanced tag detection and tracking for code comments
local M = {}
local config = require("taskforge.config")
local utils = require("taskforge.utils")
local ns = vim.api.nvim_create_namespace("taskforge_tags")

-- UUID pattern for task identification in comments
M.uuid_pattern = "%[task:([0-9a-f%-]+)%]"
-- Pattern for opted-out comments that should not be tracked
M.optout_pattern = "%[notrack%]"

function M.setup()
  M.buf_cache = {} -- Buffer cache of detected tags
  M.task_cache = {} -- Cache of task UUIDs to location

  -- Track edit state to handle debounce properly
  M.edit_state = {
    active = false,
    debounce_timer = nil,
    last_change = nil,
  }

  -- Load existing task UUIDs from taskwarrior
  M._load_tasks()

  -- Set up autocommands for buffer events
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    callback = function(evt)
      M.process_buffer(evt.buf)
    end,
  })

  -- Handle editing modes with proper debounce
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    callback = function(evt)
      M.edit_state.active = true
      M.edit_state.last_change = vim.loop.now()

      -- Reset debounce timer on each change
      M._reset_debounce_timer(evt.buf)
    end,
  })

  -- Handle when editing ends
  vim.api.nvim_create_autocmd({ "InsertLeave", "TextChangedP" }, {
    callback = function(evt)
      M.edit_state.active = false

      -- Process after a short delay to ensure all changes are completed
      M._reset_debounce_timer(evt.buf)
    end,
  })

  -- Add command for manual tag management
  vim.api.nvim_create_user_command("TaskforgeTag", function(opts)
    local subcmd = opts.fargs[1]
    if subcmd == "add" then
      M.add_tag_at_cursor()
    elseif subcmd == "remove" then
      M.remove_tag_at_cursor()
    elseif subcmd == "link" then
      M.link_tag_to_task()
    elseif subcmd == "optout" then
      M.add_optout_at_cursor()
    elseif subcmd == "process" then
      M.process_all_comments()
    end
  end, {
    nargs = 1,
    complete = function()
      return { "add", "remove", "link", "optout", "process" }
    end,
  })

  -- Set up debounce timer
  M._debounce_ms = config.get().tags.debounce or 500

  -- Set up formatter hooks
  M.setup_formatter_hooks()
end

-- Reset debounce timer with current settings
function M._reset_debounce_timer(bufnr)
  -- Cancel previous timer if it exists
  if M.edit_state.debounce_timer then
    vim.loop.timer_stop(M.edit_state.debounce_timer)
    M.edit_state.debounce_timer = nil
  end

  -- Create new timer
  M.edit_state.debounce_timer = vim.defer_fn(function()
    -- Only process if editing has stopped for a while or this is an explicit processing request
    if not M.edit_state.active or (vim.loop.now() - M.edit_state.last_change > M._debounce_ms) then
      M.process_buffer(bufnr)
      M.edit_state.debounce_timer = nil
    end
  end, M._debounce_ms)
end

-- Load existing tasks from taskwarrior
function M._load_tasks()
  local tasks = require("taskforge.tasks")

  -- Try to get tasks with annotations that have file paths
  local all_tasks = tasks.list_with_annotations()

  for _, task in ipairs(all_tasks) do
    if task.annotations then
      for _, anno in ipairs(task.annotations) do
        -- Look for file:// annotations
        local file_uri = anno.description:match("file://([^%s]+)")
        if file_uri then
          local path, line = file_uri:match("([^:]+):(%d+)")
          if path and line then
            -- Store in task cache
            M.task_cache[task.uuid] = {
              file = path,
              line = tonumber(line),
              description = task.description,
              status = task.status,
            }
          end
        end
      end
    end
  end

  utils.debug_log("TRACKER", "Loaded task cache", #vim.tbl_keys(M.task_cache))
end

-- Process all tagged comments in new file
function M.process_all_comments()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Check if multiline module is available for enhanced comment detection
  local has_multiline = pcall(require, "taskforge.multiline")

  -- Identify all comments in the buffer
  local comment_nodes = M._get_comment_nodes(bufnr)
  local tag_candidates = {}

  -- Gather all tag candidates first without processing
  for _, node in ipairs(comment_nodes) do
    local start_row, _, _, _ = node:range()
    local comment_text = vim.treesitter.get_node_text(node, bufnr)

    -- Skip if this comment has optout marker or already has UUID
    if comment_text:match(M.optout_pattern) or comment_text:match(M.uuid_pattern) then
      goto continue
    end

    -- Check for tags
    local ft = vim.bo[bufnr].filetype
    local cfg = config.get()

    for tag, def in pairs(cfg.tags.definitions or {}) do
      -- Include alternative tags in the search
      local tags_to_check = { tag }
      if def.alt then
        vim.list_extend(tags_to_check, def.alt)
      end

      -- Check each possible tag
      for _, tag_name in ipairs(tags_to_check) do
        if comment_text:match(tag_name) then
          -- Found a tag, store the info for batch processing
          table.insert(tag_candidates, {
            lnum = start_row,
            text = comment_text,
            tag = tag_name,
            def = def,
            node = node,
          })
          goto continue
        end
      end
    end

    ::continue::
  end

  -- If we found tags, show them to the user
  if #tag_candidates > 0 then
    M._process_tag_candidates(bufnr, tag_candidates)
  else
    utils.notify("No untracked tags found in file")
  end
end

-- Process tag candidates in a batch
function M._process_tag_candidates(bufnr, candidates)
  -- Group candidates by creation mode
  local auto_create = {}
  local ask_create = {}
  local manual_create = {}

  for _, candidate in ipairs(candidates) do
    if candidate.def.create == "auto" then
      table.insert(auto_create, candidate)
    elseif candidate.def.create == "ask" then
      table.insert(ask_create, candidate)
    elseif candidate.def.create == "manual" then
      table.insert(manual_create, candidate)
    end
  end

  -- Process auto-create tags silently
  for _, candidate in ipairs(auto_create) do
    M._process_tag_auto(bufnr, candidate)
  end

  -- Process manual-create tags with notification
  for _, candidate in ipairs(manual_create) do
    M._process_tag_manual(bufnr, candidate)
  end

  -- Process ask-create tags with UI
  if #ask_create > 0 then
    M._show_tag_selection(bufnr, ask_create)
  end

  -- Provide summary
  local total_processed = #auto_create + #manual_create
  if total_processed > 0 then
    utils.notify(
      string.format("Processed %d tags automatically, %d tags require confirmation", total_processed, #ask_create)
    )
  end
end

-- Process auto-create tag
function M._process_tag_auto(bufnr, candidate)
  local extract_result = M._extract_description(bufnr, candidate.node, candidate.tag)
  if not extract_result or not extract_result.description then
    utils.debug_log("TRACKER", "Failed to extract description for auto tag", candidate.tag)
    return
  end

  -- Prepare task info
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local task_info = {
    description = candidate.tag .. ": " .. extract_result.description,
    file = file_path,
    line = candidate.lnum + 1,
    project = require("taskforge.project").current(),
    tags = candidate.def.tags,
    due = candidate.def.due,
    priority = candidate.def.priority,
  }

  -- Create task automatically
  require("taskforge.tasks").create(task_info.description, task_info, function(uuid)
    if uuid then
      -- Link the UUID back to the comment
      M._link_uuid_to_comment(bufnr, candidate.lnum, uuid)
    end
  end)
end

-- Process manual-create tag
function M._process_tag_manual(bufnr, candidate)
  local extract_result = M._extract_description(bufnr, candidate.node, candidate.tag)
  if not extract_result or not extract_result.description then
    utils.debug_log("TRACKER", "Failed to extract description for manual tag", candidate.tag)
    return
  end

  -- Just notify, don't create task
  utils.notify(
    "Tag found: " .. candidate.tag .. ": " .. extract_result.description .. "\nUse :TaskforgeTag add to create task",
    vim.log.levels.INFO
  )
end

-- Show UI for selecting which tags to create tasks for
function M._show_tag_selection(bufnr, candidates)
  -- Format items for selection
  local items = {}
  for i, candidate in ipairs(candidates) do
    local extract_result = M._extract_description(bufnr, candidate.node, candidate.tag)
    local desc = extract_result and extract_result.description or "No description"

    table.insert(items, {
      text = string.format("%s: %s (line %d)", candidate.tag, desc, candidate.lnum + 1),
      index = i,
      candidate = candidate,
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
      utils.confirm_yesno("Create task for: " .. selected.text .. "?", function(choice)
        if choice == 1 then -- Yes
          -- Similar to process_tag_auto
          local extract_result = M._extract_description(bufnr, selected.candidate.node, selected.candidate.tag)
          if extract_result and extract_result.description then
            local file_path = vim.api.nvim_buf_get_name(bufnr)
            local task_info = {
              description = selected.candidate.tag .. ": " .. extract_result.description,
              file = file_path,
              line = selected.candidate.lnum + 1,
              project = require("taskforge.project").current(),
              tags = selected.candidate.def.tags,
              due = selected.candidate.def.due,
              priority = selected.candidate.def.priority,
            }

            require("taskforge.tasks").create(task_info.description, task_info, function(uuid)
              if uuid then
                M._link_uuid_to_comment(bufnr, selected.candidate.lnum, uuid)

                -- Show the next candidate
                vim.defer_fn(function()
                  -- Remove the processed item
                  table.remove(candidates, selected.index)
                  if #candidates > 0 then
                    M._show_tag_selection(bufnr, candidates)
                  else
                    utils.notify("All selected tags processed")
                  end
                end, 100)
              end
            end)
          end
        else
          -- Skip to next
          table.remove(candidates, selected.index)
          if #candidates > 0 then
            vim.defer_fn(function()
              M._show_tag_selection(bufnr, candidates)
            end, 10)
          else
            utils.notify("No tags selected for processing")
          end
        end
      end)
    else
      utils.notify("Tag processing cancelled")
    end
  end)
end

-- Extract tag description more robustly
function M._extract_description(bufnr, node, tag)
  if not node then
    return { tag = tag, description = "No description" }
  end

  local comment_text = vim.treesitter.get_node_text(node, bufnr)
  local ft = vim.bo[bufnr].filetype

  -- First try to use tag_patterns library for smart detection
  local tag_patterns = require("taskforge.tag_patterns")
  local parsed = tag_patterns.parse_tag_comment(comment_text, ft, { tag })

  if parsed and parsed.description then
    return parsed
  end

  -- Fallbacks for different formats
  local desc

  -- Try format with colon: "TAG: description"
  desc = comment_text:match(tag .. ":%s*(.+)")
  if desc then
    return { tag = tag, description = desc:gsub("%*/+$", ""):gsub("%s+$", ""):gsub("^%s+", "") }
  end

  -- Try format with parentheses: "TAG(meta): description"
  desc = comment_text:match(tag .. "%([^)]*%):%s*(.+)")
  if desc then
    return { tag = tag, description = desc:gsub("%*/+$", ""):gsub("%s+$", ""):gsub("^%s+", "") }
  end

  -- Try any text after the tag
  desc = comment_text:match(tag .. "[^:]*:%s*(.+)")
  if desc then
    return { tag = tag, description = desc:gsub("%*/+$", ""):gsub("%s+$", ""):gsub("^%s+", "") }
  end

  -- Try to get the rest of the line after the tag
  desc = comment_text:match(tag .. "(.+)")
  if desc then
    return { tag = tag, description = desc:gsub("%*/+$", ""):gsub("%s+$", ""):gsub("^%s+", "") }
  end

  -- Default fallback
  return { tag = tag, description = "No description" }
end

-- Get comment nodes from buffer using TreeSitter
function M._get_comment_nodes(bufnr)
  bufnr = bufnr or 0

  -- Check buffer validity
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  -- Check filetype
  local ft = vim.bo[bufnr].filetype
  if ft == "" or ft == "dashboard" or ft == "snacks_dashboard" or ft == "NvimTree" or vim.bo[bufnr].buftype ~= "" then
    return {}
  end

  -- Ensure TreeSitter is available
  if not vim.treesitter then
    utils.debug_log("TRACKER", "TreeSitter not available")
    return {}
  end

  -- Skip potential errors with pcall
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    -- No parser available for this filetype
    return {}
  end

  local tree
  ok, tree = pcall(function()
    return parser:parse()[1]
  end)
  if not ok or not tree then
    utils.debug_log("TRACKER", "Could not parse buffer")
    return {}
  end

  local root = tree:root()
  if not root then
    utils.debug_log("TRACKER", "No root node found")
    return {}
  end

  -- Try to create a query for comments
  local query
  ok, query = pcall(
    vim.treesitter.query.parse,
    parser:lang(),
    [[
    (comment) @comment
    (line_comment) @comment
    (block_comment) @comment
  ]]
  )

  if not ok or not query then
    -- Try a more generic approach if the specific comment query fails
    ok, query = pcall(vim.treesitter.query.parse, parser:lang(), "(comment) @comment")
    if not ok or not query then
      utils.debug_log("TRACKER", "Could not create comment query for " .. ft)
      return {}
    end
  end

  local comments = {}

  -- Use pcall to safely iterate over query captures
  ok, _ = pcall(function()
    for id, node in query:iter_captures(root, bufnr, 0, -1) do
      local type = query.captures[id] -- should be "comment"
      if type == "comment" then
        table.insert(comments, node)
      end
    end
  end)

  if not ok then
    utils.debug_log("TRACKER", "Error processing comment query")
    return {}
  end

  utils.debug_log("TRACKER", "Found " .. #comments .. " comment nodes")
  return comments
end

-- Process buffer for code tags
function M.process_buffer(bufnr)
  bufnr = bufnr or 0

  -- Make sure buffer exists and is valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Check file type and buffer type
  local ft = vim.bo[bufnr].filetype
  local buftype = vim.bo[bufnr].buftype

  -- Skip special buffers or filetypes
  if
    ft == ""
    or ft == "dashboard"
    or ft == "snacks_dashboard"
    or ft == "NvimTree"
    or ft:match("^fugitive")
    or buftype ~= ""
  then
    return
  end

  local cfg = config.get()

  -- Skip if filetype isn't enabled or if there's no tag configuration
  if not cfg.tags or not cfg.tags.enable then
    return
  end

  if cfg.tags.enabled_ft and cfg.tags.enabled_ft[1] ~= "*" and not vim.tbl_contains(cfg.tags.enabled_ft, ft) then
    return
  end

  -- Clear previous extmarks
  M.clear_tags(bufnr)

  -- Get comment nodes using TreeSitter
  local comment_nodes = M._get_comment_nodes(bufnr)

  -- Process each comment for tags
  for _, node in ipairs(comment_nodes) do
    local start_row, _, _, _ = node:range() -- Only use start_row, ignoring other values
    local comment_text = vim.treesitter.get_node_text(node, bufnr)

    if comment_text and #comment_text > 0 then
      utils.debug_log("TRACKER", "Processing comment", comment_text)

      -- Skip if comment has opt-out marker
      if comment_text:match(M.optout_pattern) then
        utils.debug_log("TRACKER", "Skipping opted-out comment", comment_text:sub(1, 50))
        goto continue
      end

      -- First check if this comment has a task UUID
      local uuid = comment_text:match(M.uuid_pattern)
      if uuid then
        -- This is a tracked comment, verify and update the cache
        utils.debug_log("TRACKER", "Found tracked comment with UUID", uuid)
        M.handle_tracked_comment(bufnr, start_row, comment_text, uuid)
      else
        -- Try to use tag pattern library for smart detection, but only for configured tags
        local tag_patterns = require("taskforge.tag_patterns")

        -- Create a list of all configured tags (including alternatives)
        local configured_tags = {}
        for tag, def in pairs(cfg.tags.definitions or {}) do
          table.insert(configured_tags, tag)
          if def.alt then
            for _, alt in ipairs(def.alt) do
              table.insert(configured_tags, alt)
            end
          end
        end

        -- Only parse with configured tags
        local parsed = tag_patterns.parse_tag_comment(comment_text, ft, configured_tags)

        if parsed then
          -- Found a configured tag using our pattern library
          utils.debug_log("TRACKER", "Found configured tag using pattern library", parsed)

          -- Look for the tag in config to get its definition
          for tag, def in pairs(cfg.tags.definitions or {}) do
            -- Check if the detected tag matches this config entry
            if parsed.tag == tag or (def.alt and vim.tbl_contains(def.alt, parsed.tag)) then
              utils.debug_log("TRACKER", "Found matching tag config", tag)

              -- Use the main tag from config if an alternative was found
              local canonical_tag = tag
              if parsed.tag ~= tag then
                canonical_tag = tag -- Use the main tag defined in config
              else
                canonical_tag = parsed.tag -- Keep the same tag
              end

              M.handle_tag(bufnr, start_row, comment_text, canonical_tag, def, parsed.description)
              goto continue
            end
          end
        end

        -- Fall back to configured patterns if smart detection failed
        for tag, def in pairs(cfg.tags.definitions or {}) do
          -- Include alternative tags in the search
          local tags_to_check = { tag }
          if def.alt then
            vim.list_extend(tags_to_check, def.alt)
          end

          -- Check each possible tag
          for _, tag_name in ipairs(tags_to_check) do
            local tag_pattern = tag_name
            if def.pattern then
              tag_pattern = def.pattern:gsub("TAG", tag_name)
            end

            if comment_text:match(tag_pattern) then
              utils.debug_log("TRACKER", "Found tag with fallback pattern", tag_name)
              M.handle_tag(bufnr, start_row, comment_text, tag_name, def)
              goto continue
            end
          end
        end
      end

      ::continue::
    end
  end

  -- Check for removed or modified tags
  M._check_removed_tags(bufnr)
end

-- Clear all tag extmarks in a buffer
function M.clear_tags(bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  -- Clear cache for this buffer
  M.buf_cache[bufnr] = nil
end

-- Add a visual marker for a tag
function M._add_tag_marker(bufnr, lnum, tag)
  vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
    virt_text = { { "⚑ " .. tag, "Comment" } },
    virt_text_pos = "eol",
  })
end

-- Process a multiline comment
function M.process_multiline_comment(bufnr, lnum)
  -- This function uses the multiline module to handle multiline comments
  local multiline = require("taskforge.multiline")
  return multiline.process_comment_at_cursor()
end

-- Add opt-out marker to a comment
function M._add_optout_to_comment(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]

  -- Add [notrack] marker to the comment
  local new_line

  -- Check if line ends with a block comment marker
  if line:match("%*/+%s*$") then
    -- Insert before closing */
    new_line = line:gsub("%*/+%s*$", " [notrack] */")
  else
    -- Just append
    new_line = line .. " [notrack]"
  end

  vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
  utils.notify("Added [notrack] marker to prevent future prompts", vim.log.levels.INFO)
end

-- Helper function to escape pattern special characters
function escape_pattern(text)
  return text:gsub("[%%%(%)%.%[%]%*%+%-%?%^%$]", "%%%1")
end

-- Handle a tracked comment (with UUID)
function M.handle_tracked_comment(bufnr, lnum, comment_text, uuid)
  local cfg = config.get() -- Explicitly get config

  -- Check if we have this task in our cache
  if not M.task_cache[uuid] then
    -- Load latest task data from taskwarrior
    local tasks = require("taskforge.tasks")
    local task = tasks.get_task(uuid)

    if task then
      M.task_cache[uuid] = {
        file = vim.api.nvim_buf_get_name(bufnr),
        line = lnum + 1,
        description = task.description,
        status = task.status,
      }
    else
      -- Task might have been deleted, handle this case
      utils.debug_log("TRACKER", "UUID in comment doesn't match any task", uuid)

      -- Warn the user and offer to remove the UUID
      utils.confirm_yesno("Task " .. uuid .. " no longer exists. Remove UUID from comment?", function(choice)
        if choice == 1 then
          -- Remove UUID from comment
          local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
          local new_line = line:gsub("%s*%[task:" .. uuid .. "%]", "")
          vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
          utils.notify("UUID removed from comment", vim.log.levels.INFO)
        end
      end)
      return
    end
  end

  -- Check if UUID format in comment has been modified
  local original_uuid_marker = "[task:" .. uuid .. "]"
  if not comment_text:match(escape_pattern(original_uuid_marker)) then
    -- UUID is present but in modified form, this could break tracking
    utils.debug_log("TRACKER", "UUID format modified", uuid)

    -- Warn the user about modified UUID format
    utils.confirm_yesno(
      "UUID format appears to be modified, which could break task tracking. Restore original format?",
      function(choice)
        if choice == 1 then
          -- Get current line
          local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]

          -- Attempt to fix the UUID format
          local new_line = line:gsub("%[task:[0-9a-f%-]+%]", original_uuid_marker)
          vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
          utils.notify("UUID format restored", vim.log.levels.INFO)
        end
      end
    )
  end

  -- Update cache with current location
  M.task_cache[uuid].file = vim.api.nvim_buf_get_name(bufnr)
  M.task_cache[uuid].line = lnum + 1

  -- Store in buffer cache
  M.buf_cache[bufnr] = M.buf_cache[bufnr] or {}
  M.buf_cache[bufnr][lnum] = {
    uuid = uuid,
    text = comment_text,
  }

  -- Extract tag from comment - use the same logic as handle_tag
  local tag_found = false

  for tag, def in pairs(cfg.tags.definitions or {}) do
    -- Include alternative tags
    local tags_to_check = { tag }
    if def.alt then
      vim.list_extend(tags_to_check, def.alt)
    end

    for _, tag_name in ipairs(tags_to_check) do
      if comment_text:match(tag_name) then
        -- Add visual indicator
        M._add_tag_marker(bufnr, lnum, tag_name)
        tag_found = true
        break
      end
    end
    if tag_found then
      break
    end
  end

  -- If no known tag found, use generic marker
  if not tag_found then
    M._add_tag_marker(bufnr, lnum, "TASK")
  end
end

-- Handle a detected tag without UUID
function M.handle_tag(bufnr, lnum, comment_text, tag, def, parsed_description)
  local cfg = config.get() -- Explicitly get config

  -- Use parsed description if provided, otherwise extract from comment
  local desc
  if parsed_description then
    desc = parsed_description
  else
    -- Use the more robust extraction method
    local extract_result = M._extract_description(bufnr, nil, tag)
    desc = extract_result and extract_result.description or "No description"

    -- If no node was provided (called directly), try to extract from comment_text
    if not extract_result or not extract_result.description then
      -- Fall back to simple extraction from text
      desc = comment_text:match(tag .. ":%s*(.+)")
      if not desc then
        desc = "No description"
      end
    end
  end

  utils.debug_log("TRACKER", "Extracted description", { tag = tag, description = desc })

  -- Store metadata
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local task_info = {
    description = tag .. ": " .. desc,
    file = file_path,
    line = lnum + 1,
    project = require("taskforge.project").current(),
    tags = def.tags,
    due = def.due,
    priority = def.priority,
  }

  -- Cache tag info for this buffer
  M.buf_cache[bufnr] = M.buf_cache[bufnr] or {}
  M.buf_cache[bufnr][lnum] = {
    text = comment_text,
    task_info = task_info,
  }

  -- Add visual marker
  M._add_tag_marker(bufnr, lnum, tag)

  -- Check if the comment already has a task associated with it
  if comment_text:match(M.uuid_pattern) then
    -- Already tracked, no need to create a new task
    return
  end

  -- Also check if the comment has opted out from tracking
  if comment_text:match(M.optout_pattern) then
    -- Opted out, don't create a task
    return
  end

  -- Create task based on configuration
  if def.create == "auto" then
    utils.debug_log("TRACKER", "Auto-creating task for tag", tag)
    require("taskforge.tasks").create(task_info.description, task_info, function(uuid)
      if uuid then
        -- Link the UUID back to the comment
        M._link_uuid_to_comment(bufnr, lnum, uuid)
      end
    end)
  elseif def.create == "ask" then
    -- Use centralized confirmation dialog
    utils.confirm_yesno("Create task for: " .. task_info.description .. "?", function(choice)
      if choice == 1 then
        require("taskforge.tasks").create(task_info.description, task_info, function(uuid)
          if uuid then
            -- Link the UUID back to the comment
            M._link_uuid_to_comment(bufnr, lnum, uuid)
          end
        end)
      else
        -- User declined, offer to add opt-out marker
        utils.confirm_yesno("Add [notrack] marker to prevent future prompts?", function(choice2)
          if choice2 == 1 then
            -- Add opt-out marker
            M._add_optout_to_comment(bufnr, lnum)
          end
        end)
      end
    end)
  elseif def.create == "manual" then
    utils.notify(
      "Tag found: " .. task_info.description .. "\nUse :TaskforgeTag add to create task",
      vim.log.levels.INFO
    )
  end
end

-- Link a UUID to a comment by inserting it into the comment text
function M._link_uuid_to_comment(bufnr, lnum, uuid)
  -- Debug the linking process
  utils.debug_log("TRACKER", "Attempting to link UUID to comment", {
    uuid = uuid,
    buffer = bufnr,
    line = lnum + 1,
    valid_buffer = vim.api.nvim_buf_is_valid(bufnr),
  })

  -- Schedule on the main thread with higher priority using vim.schedule
  vim.schedule(function()
    -- Verify buffer still exists
    if not vim.api.nvim_buf_is_valid(bufnr) then
      utils.debug_log("TRACKER", "Buffer no longer valid", bufnr)
      return
    end

    -- Get the current line count to ensure the line still exists
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if lnum >= line_count then
      utils.debug_log("TRACKER", "Line no longer exists", lnum)
      return
    end

    -- Try to use multiline module if available
    local has_multiline, multiline = pcall(require, "taskforge.multiline")
    if has_multiline then
      local context = multiline.detect_comment_context(bufnr, lnum)
      if context.is_comment then
        if multiline.add_uuid_to_comment(bufnr, context, uuid) then
          -- UUID added to multiline comment successfully
          utils.debug_log("TRACKER", "UUID added to multiline comment", uuid)
          utils.notify("Task created and linked to comment", vim.log.levels.INFO)

          -- Update cache
          M.task_cache[uuid] = {
            file = vim.api.nvim_buf_get_name(bufnr),
            line = lnum + 1,
            status = "pending",
          }

          return
        end
      end
    end

    -- Fallback: Get the current line
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]

    -- Debug the line content
    utils.debug_log("TRACKER", "Current line content", line)

    -- Check if UUID already exists
    if line:match(M.uuid_pattern) then
      utils.debug_log("TRACKER", "UUID already exists in line", uuid)
      return
    end

    -- Add UUID marker to the end of the comment
    local new_line

    -- Different comment endings based on filetype
    local ft = vim.bo[bufnr].filetype
    if ft == "lua" or ft == "python" or ft == "bash" or ft == "sh" or ft == "zsh" then
      -- Single line comment, just append
      new_line = line .. " [task:" .. uuid .. "]"
    elseif ft == "c" or ft == "cpp" or ft == "java" or ft == "javascript" or ft == "typescript" or ft == "go" then
      -- Might be block comment, look for */
      if line:match("%*/") then
        -- Insert before closing */
        new_line = line:gsub("%*/", " [task:" .. uuid .. "] */")
      else
        -- Just append
        new_line = line .. " [task:" .. uuid .. "]"
      end
    else
      -- Default case, just append
      new_line = line .. " [task:" .. uuid .. "]"
    end

    -- Debug the new line content
    utils.debug_log("TRACKER", "New line content", new_line)

    -- Update the line
    vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

    -- Update cache
    M.task_cache[uuid] = {
      file = vim.api.nvim_buf_get_name(bufnr),
      line = lnum + 1,
      status = "pending",
    }

    utils.debug_log("TRACKER", "Successfully linked UUID to comment", uuid)
    utils.notify("Task created and linked to comment", vim.log.levels.INFO)
  end)
end

-- Check for removed or modified tags in a buffer
function M._check_removed_tags(bufnr)
  local cfg = config.get() -- Explicitly get config

  -- If no cache for this buffer, nothing to do
  if not M.buf_cache or not M.buf_cache[bufnr] then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Check each cached tag
  for lnum, tag_data in pairs(M.buf_cache[bufnr]) do
    -- Line still exists?
    if lnum < #lines then
      local line = lines[lnum + 1]

      -- If the line has changed significantly or tag no longer exists
      if not tag_data.text or not vim.startswith(line, tag_data.text:sub(1, 10)) then
        -- Tag was removed or significantly modified
        if tag_data.uuid then
          -- This was a tracked tag with UUID
          utils.debug_log("TRACKER", "Tag with UUID removed or modified", tag_data.uuid)

          -- Find the tag definition that would have created this task
          local tag_def = nil
          for tag, def in pairs(cfg.tags.definitions) do
            if tag_data.text:match(tag) then
              tag_def = def
              break
            end

            -- Check alternative tags
            if def.alt then
              for _, alt in ipairs(def.alt) do
                if tag_data.text:match(alt) then
                  tag_def = def
                  break
                end
              end
            end

            if tag_def then
              break
            end
          end

          -- Handle based on close action
          if tag_def and tag_def.close == "auto" then
            require("taskforge.tasks").done(tag_data.uuid)
            utils.notify("Task automatically marked done (tag removed)", vim.log.levels.INFO)
          elseif tag_def and tag_def.close == "ask" then
            utils.confirm_yesno("Mark task as done? (Tag removed)", function(choice)
              if choice == 1 then
                require("taskforge.tasks").done(tag_data.uuid)
                utils.notify("Task marked as done", vim.log.levels.INFO)
              end
            end)
          elseif tag_def and tag_def.close == "manual" then
            utils.notify(
              "Tag removed. Use :Taskforge done " .. tag_data.uuid .. " to mark task as done",
              vim.log.levels.WARN
            )
          end
        end
      else
        -- Line still exists but might have been modified
        -- Check if the UUID is still intact
        if tag_data.uuid then
          local uuid_present = line:match(M.uuid_pattern)
          if not uuid_present or uuid_present ~= tag_data.uuid then
            -- UUID was removed or modified, warn the user
            utils.debug_log("TRACKER", "UUID modified or removed", {
              original = tag_data.uuid,
              current = uuid_present,
            })

            -- Only warn if this isn't part of an ongoing edit
            if not M.edit_state.active then
              utils.confirm_yesno("Task reference (UUID) was modified or removed. Restore it?", function(choice)
                if choice == 1 then
                  -- Try to restore the UUID
                  local new_line = line
                  if uuid_present then
                    -- Replace incorrect UUID
                    new_line = line:gsub("%[task:[0-9a-f%-]+%]", "[task:" .. tag_data.uuid .. "]")
                  else
                    -- Add UUID back
                    new_line = M._add_uuid_to_line(line, tag_data.uuid)
                  end

                  vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
                  utils.notify("Task reference restored", vim.log.levels.INFO)
                end
              end)
            end
          end
        end
      end
    end
  end
end

-- Helper function to add UUID to a line based on comment style
function M._add_uuid_to_line(line, uuid)
  -- Different comment endings based on line content
  if line:match("%*/") then
    -- Block comment, insert before closing */
    return line:gsub("%*/", " [task:" .. uuid .. "] */")
  else
    -- Just append
    return line .. " [task:" .. uuid .. "]"
  end
end

-- Add a tag at the current cursor position
function M.add_tag_at_cursor()
  -- Get current line
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line = vim.api.nvim_get_current_line()

  -- Check if line is a comment
  local bufnr = vim.api.nvim_get_current_buf()
  local is_comment = false

  -- Try to use multiline module first if available
  local has_multiline, multiline = pcall(require, "taskforge.multiline")
  if has_multiline then
    local context = multiline.detect_comment_context(bufnr, lnum)
    if context.is_comment then
      is_comment = true

      -- If it's already a comment, check for existing tags
      local comment_lines = multiline.get_full_comment(bufnr, lnum)

      if comment_lines and #comment_lines > 0 then
        -- Get configured tags
        local cfg = config.get()
        local available_tags = {}

        for tag, def in pairs(cfg.tags.definitions or {}) do
          table.insert(available_tags, tag)
          if def.alt then
            for _, alt in ipairs(def.alt) do
              table.insert(available_tags, alt)
            end
          end
        end

        -- Look for existing tags
        local tag_info = multiline.find_tag_in_comment(comment_lines, available_tags)

        if tag_info then
          -- Tag exists, process it directly
          multiline.process_comment_at_cursor()
          return
        end

        -- No tag found, continue to add one
      end
    end
  end

  -- Fallback to treesitter-based comment detection if multiline module didn't find anything

  -- Use treesitter to check if cursor is in a comment
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if ok and parser then
    local tree = parser:parse()[1]
    if tree then
      local root = tree:root()
      if root then
        -- Get node at cursor
        local node = root:named_descendant_for_range(lnum, 0, lnum, #line)
        while node do
          if node:type() == "comment" or node:type() == "line_comment" or node:type() == "block_comment" then
            is_comment = true
            break
          end
          node = node:parent()
        end
      end
    end
  end

  if not is_comment then
    -- Not a comment, ask for tag type
    local tags = {}
    local cfg = config.get()
    for tag, _ in pairs(cfg.tags.definitions) do
      table.insert(tags, tag)
    end

    vim.ui.select(tags, {
      prompt = "Select tag type:",
    }, function(tag)
      if tag then
        -- Create the comment with tag
        local comment_prefix
        local ft = vim.bo.filetype

        if ft == "lua" or ft == "python" or ft == "bash" or ft == "sh" then
          comment_prefix = "# "
        elseif ft == "vim" then
          comment_prefix = '" '
        elseif
          ft == "c"
          or ft == "cpp"
          or ft == "java"
          or ft == "javascript"
          or ft == "typescript"
          or ft == "go"
          or ft == "rust"
        then
          comment_prefix = "// "
        else
          comment_prefix = "// "
        end

        -- Ask for description
        vim.ui.input({
          prompt = "Description:",
        }, function(desc)
          if desc then
            local new_line = comment_prefix .. tag .. ": " .. desc
            vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

            -- Process the buffer to create the task
            M.process_buffer(bufnr)
          end
        end)
      end
    end)
  else
    -- Already a comment, check if it has a tag
    local has_tag = false
    local cfg = config.get()

    for tag, def in pairs(cfg.tags.definitions) do
      if line:match(tag) then
        has_tag = true
        break
      end

      if def.alt then
        for _, alt in ipairs(def.alt) do
          if line:match(alt) then
            has_tag = true
            break
          end
        end
      end

      if has_tag then
        break
      end
    end

    if has_tag then
      -- Already has a tag, create task for it
      M.process_buffer(bufnr)
    else
      -- Comment without tag, ask for tag type
      local tags = {}
      for tag, _ in pairs(cfg.tags.definitions) do
        table.insert(tags, tag)
      end

      vim.ui.select(tags, {
        prompt = "Select tag type for this comment:",
      }, function(tag)
        if tag then
          -- Add tag to the comment
          local new_line = line:gsub('^(%s*[/#"%*]+%s*)', "%1" .. tag .. ": ")
          vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

          -- Process the buffer to create the task
          M.process_buffer(bufnr)
        end
      end)
    end
  end
end

-- Add opt-out marker at cursor position
function M.add_optout_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

  -- Add the opt-out marker
  M._add_optout_to_comment(bufnr, lnum)

  -- Re-process the buffer so the comment won't be tracked
  M.process_buffer(bufnr)
end

-- Remove a tag at cursor position
function M.remove_tag_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line = vim.api.nvim_get_current_line()

  -- Check if line has a UUID
  local uuid = line:match(M.uuid_pattern)
  if uuid then
    -- Use centralized confirmation dialog
    utils.confirm_yesno("Remove tag and mark task as done?", function(choice)
      if choice == 1 then
        -- Mark task as done
        require("taskforge.tasks").done(uuid)

        -- Remove UUID from line
        local new_line = line:gsub("%s*%[task:[0-9a-f%-]+%]", "")
        vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

        utils.notify("Task marked as done and tag removed", vim.log.levels.INFO)
      end
    end)
  else
    -- No UUID, check if it's a tag line
    local has_tag = false
    local cfg = config.get()

    for tag, _ in pairs(cfg.tags.definitions) do
      if line:match(tag) then
        has_tag = true
        break
      end
    end

    if has_tag then
      -- Just remove the tag prefix
      local new_line = line:gsub('(%s*[/#"%*]+%s*)[A-Z]+:%s*', "%1")
      vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

      utils.notify("Tag removed", vim.log.levels.INFO)
    else
      utils.notify("No tag found at cursor position", vim.log.levels.WARN)
    end
  end
end

-- Handle formatter events to fix any tasks broken by formatting
function M.handle_format_event(bufnr)
  -- This should be called after a formatter runs
  utils.debug_log("TRACKER", "Handling format event", bufnr)

  -- Wait a short delay to ensure formatting is complete
  vim.defer_fn(function()
    -- We need to check all known UUIDs for this buffer
    -- and make sure they're still properly formatted
    local uuids_to_check = {}

    -- Find UUIDs for this file
    local file_path = vim.api.nvim_buf_get_name(bufnr)
    for uuid, location in pairs(M.task_cache) do
      if location.file == file_path then
        table.insert(uuids_to_check, uuid)
      end
    end

    if #uuids_to_check > 0 then
      utils.debug_log("TRACKER", "Checking UUIDs after formatting", #uuids_to_check)

      -- Search the entire buffer for these UUIDs
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local fixed_count = 0

      for uuid, _ in pairs(M.task_cache) do
        local found = false
        local needs_fix = false

        for i, line in ipairs(lines) do
          -- Check if line has a valid UUID marker
          local exact_uuid = line:match(M.uuid_pattern)
          if exact_uuid and exact_uuid == uuid then
            found = true
            -- UUID is properly formatted
            break
          end

          -- Check if line has the UUID but in an incorrect format
          if line:match(uuid) then
            found = true
            needs_fix = true

            -- Fix the UUID format
            local new_line
            if line:match("%[task:") then
              -- Format is wrong but bracket exists
              new_line = line:gsub("%[task:[^%]]*%]", "[task:" .. uuid .. "]")
            else
              -- No bracket format, add it
              new_line = M._add_uuid_to_line(line, uuid)
            end

            vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { new_line })
            fixed_count = fixed_count + 1
            break
          end
        end

        if found and not needs_fix then
          utils.debug_log("TRACKER", "UUID already properly formatted", uuid)
        elseif found and needs_fix then
          utils.debug_log("TRACKER", "UUID format fixed", uuid)
        else
          utils.debug_log("TRACKER", "UUID not found after formatting", uuid)
        end
      end

      if fixed_count > 0 then
        utils.notify("Fixed " .. fixed_count .. " task references after formatting", vim.log.levels.INFO)
      end
    end
  end, 100)
end

-- Manually link a comment to an existing task
function M.link_tag_to_task()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line = vim.api.nvim_get_current_line()

  -- Check if line already has UUID
  if line:match(M.uuid_pattern) then
    utils.notify("Comment already linked to a task", vim.log.levels.WARN)
    return
  end

  -- Get available tasks
  local tasks = require("taskforge.tasks")
  local all_tasks = tasks.list()

  -- Format tasks for selection
  local items = {}
  for _, task in ipairs(all_tasks) do
    table.insert(items, {
      text = task.description,
      uuid = task.uuid,
    })
  end

  -- Let user select a task
  vim.ui.select(items, {
    prompt = "Select task to link:",
    format_item = function(item)
      return item.text
    end,
  }, function(selected)
    if selected then
      -- Link the UUID to the comment
      M._link_uuid_to_comment(bufnr, lnum, selected.uuid)
    end
  end)
end

-- Handle task status change
function M.handle_task_status_change(uuid, new_status)
  local cfg = config.get() -- Explicitly get config

  -- Check if we're tracking this task
  if M.task_cache[uuid] then
    local location = M.task_cache[uuid]

    if new_status == "completed" then
      -- Task was completed, remove or update the tag
      if vim.fn.filereadable(location.file) == 1 then
        -- Open the file
        local buf = vim.fn.bufadd(location.file)
        vim.fn.bufload(buf)

        -- Check the line
        if location.line and location.line <= vim.api.nvim_buf_line_count(buf) then
          local line = vim.api.nvim_buf_get_lines(buf, location.line - 1, location.line, false)[1]

          -- Check if UUID exists in line
          if line:match(M.uuid_pattern) then
            -- Remove the UUID tag or the whole line based on config
            local remove_tag = cfg.tags and cfg.tags.remove_on_done

            if remove_tag then
              -- Remove the entire line or just the tag
              if cfg.tags.remove_line_on_done then
                vim.api.nvim_buf_set_lines(buf, location.line - 1, location.line, false, {})
              else
                -- Just remove the tag part
                local new_line = line:gsub("%s*[A-Z]+:%s*", ""):gsub("%s*%[task:[0-9a-f%-]+%]", "")
                vim.api.nvim_buf_set_lines(buf, location.line - 1, location.line, false, { new_line })
              end

              utils.debug_log("TRACKER", "Removed tag from completed task", uuid)
            else
              -- Mark it as DONE instead
              local new_line = line:gsub("([A-Z]+):", "DONE:")
              vim.api.nvim_buf_set_lines(buf, location.line - 1, location.line, false, { new_line })

              utils.debug_log("TRACKER", "Updated tag to DONE for completed task", uuid)
            end
          end
        end
      end
    end

    -- Update cache
    M.task_cache[uuid].status = new_status
  end
end

-- Set up autocommand for formatter integration
function M.setup_formatter_hooks()
  -- Try to hook into common formatters
  vim.api.nvim_create_autocmd("User", {
    pattern = { "FormatPre", "FormatPost", "ConformPost" },
    callback = function(evt)
      if evt.match == "FormatPre" then
        -- Store pre-format state if needed
      elseif evt.match == "FormatPost" or evt.match == "ConformPost" then
        -- Fix any formatting issues
        M.handle_format_event(vim.api.nvim_get_current_buf())
      end
    end,
  })
end

return M

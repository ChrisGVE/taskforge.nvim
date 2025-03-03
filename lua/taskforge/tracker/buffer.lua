-- lua/taskforge/tracker/buffer.lua
-- Buffer processing and comment detection

local M = {}
local utils = require("taskforge.utils")
local core = require("taskforge.tracker.core")
local config = require("taskforge.config")

-- Namespace for buffer extmarks
local ns = nil

-- Setup the buffer module
function M.setup()
  -- Create namespace for extmarks
  ns = core.get_namespace()
end

-- Process a buffer for task tags
-- @param bufnr number Buffer number
-- @param initial boolean Whether this is initial processing (first time seen)
-- @param force_scan boolean Force a full scan even if already processed
function M.process(bufnr, initial_scan, force_scan)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Make sure buffer exists and is valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Check if language module supports this buffer
  local lang = require("taskforge.lang")
  if not lang.is_supported(bufnr) then
    return
  end

  -- Get tags configuration
  local cfg = config.get().tags
  if not cfg or not cfg.enable then
    return
  end

  -- Clear previous tag markers
  M.clear_markers(bufnr)

  -- Initialize tracking for this buffer if needed
  core.initialize_buffer_tracking(bufnr)

  -- Do an initial scan only if this is the first time seeing the buffer
  -- or if force_scan is true (manual command)
  if initial_scan or force_scan then
    -- Find all untracked tags in the buffer
    local untracked_tags = M.find_untracked_tags(bufnr)

    -- Process tags in batch if there are any
    if #untracked_tags > 0 then
      -- Use new UI system for batch processing
      utils.debug_log("BUFFER", "Starting batch processing with UI system")
      -- Defer the UI processing to avoid BufEnter autocmd issues
      vim.schedule(function()
        local ui = require("taskforge.ui")
        ui.process_batch_tags(bufnr, untracked_tags)
      end)
      return
    end
  end

  -- Regular processing for tracked tags
  M.process_tracked_tags(bufnr)

  -- Check for removed or modified tags
  M.check_removed_tags(bufnr)

  -- Mark buffer as processed
  core.set_buffer_processed(bufnr)
end

-- Clear all tag markers in a buffer
function M.clear_markers(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  -- Keep the tag cache but clear the visual indicators
  -- We'll update them during processing
end

-- Find all comment nodes using TreeSitter
function M.find_comment_nodes(bufnr)
  -- Try to use TreeSitter if available
  if vim.treesitter then
    -- First try using TreeSitter API
    local ok, nodes = pcall(M._find_nodes_with_treesitter, bufnr)
    if ok and nodes and #nodes > 0 then
      return nodes
    end
  end

  -- Fall back to language module for non-TreeSitter approach
  local lang_module = require("taskforge.lang").get_for_buffer(bufnr)
  return lang_module.find_comment_lines(bufnr)
end

-- Find comment nodes with TreeSitter
function M._find_nodes_with_treesitter(bufnr)
  local comments = {}

  -- Get parser for buffer
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    utils.debug_log("BUFFER", "No parser available for buffer", bufnr)
    return {}
  end

  -- Parse buffer
  local tree = parser:parse()[1]
  if not tree then
    utils.debug_log("BUFFER", "Failed to parse buffer", bufnr)
    return {}
  end

  local root = tree:root()
  if not root then
    utils.debug_log("BUFFER", "No root node found", bufnr)
    return {}
  end

  -- Query for comments
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
      utils.debug_log("BUFFER", "Could not create comment query for buffer", bufnr)
      return {}
    end
  end

  -- Iterate over query captures
  local iter_ok, _ = pcall(function()
    for id, node in query:iter_captures(root, bufnr, 0, -1) do
      local type = query.captures[id] -- should be "comment"
      if type == "comment" then
        table.insert(comments, node)
      end
    end
  end)

  if not iter_ok then
    utils.debug_log("BUFFER", "Error iterating over comment nodes", bufnr)
    return {}
  end

  return comments
end

-- Find all untracked tags in a buffer
function M.find_untracked_tags(bufnr)
  local untracked_tags = {}
  local cfg = config.get().tags

  -- Get comment nodes - debug the result
  local comment_nodes = M.find_comment_nodes(bufnr)
  utils.debug_log("BUFFER", "Found " .. #comment_nodes .. " comments in buffer")

  -- Get buffer name for debugging
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  utils.debug_log("BUFFER", "Processing buffer", bufname)

  -- Add direct debug for TODO tags in buffer
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  if content:match("TODO") then
    utils.debug_log("BUFFER", "Buffer contains TODO, found with direct match")
  end

  for _, node in ipairs(comment_nodes) do
    -- Extract node information
    local start_row, _, end_row, _ = node:range()
    local comment_text = vim.treesitter.get_node_text(node, bufnr)

    utils.debug_log("BUFFER", "Comment at line " .. (start_row + 1), comment_text:sub(1, 50))

    -- Skip if already has UUID or opted out
    if comment_text:match(core.constants.uuid_pattern) or comment_text:match(core.constants.optout_pattern) then
      utils.debug_log("BUFFER", "Comment already has UUID or opted out - skipping")
      goto continue
    end

    -- Check for supported tags
    for tag, def in pairs(cfg.definitions or {}) do
      -- Check main tag and alternatives
      local tags_to_check = { tag }
      if def.alt then
        vim.list_extend(tags_to_check, def.alt)
      end

      -- Look for any matching tag
      for _, tag_name in ipairs(tags_to_check) do
        if comment_text:match(tag_name) then
          utils.debug_log("BUFFER", "Found tag " .. tag_name .. " in comment")

          -- Extract tag info using language module
          local lang = require("taskforge.lang").get_for_buffer(bufnr)
          local info = lang.extract_tag_info(comment_text, tag_name)
          local description = info and info.description or "No description"

          -- Found a tag, add to candidates list
          table.insert(untracked_tags, {
            lnum = start_row,
            text = comment_text,
            tag = tag_name,
            def = def,
            node = node,
            description = description,
            selected = def.create == "auto", -- Pre-select auto tags
          })
          goto continue
        end
      end
    end

    ::continue::
  end

  utils.debug_log("BUFFER", "Found " .. #untracked_tags .. " untracked tags")
  return untracked_tags
end

-- Group and process candidates by their configuration type
-- @param bufnr number Buffer number
-- @param candidates table Tag candidates
-- @return table Result with categorized tags
function M.process_candidates_by_type(bufnr, candidates)
  local auto_processed = 0
  local manual_processed = 0
  local interactive = {}

  -- Group by tag type
  for _, candidate in ipairs(candidates) do
    if candidate.def.create == "auto" then
      -- Auto create task
      M.process_auto_tag(bufnr, candidate)
      auto_processed = auto_processed + 1
    elseif candidate.def.create == "manual" then
      -- Show notification
      M.process_manual_tag(bufnr, candidate)
      manual_processed = manual_processed + 1
    else
      -- Add to interactive list for user decision
      table.insert(interactive, candidate)
    end
  end

  return {
    auto_processed = auto_processed,
    manual_processed = manual_processed,
    interactive = interactive,
  }
end

-- Process a tag for auto-creation
function M.process_auto_tag(bufnr, candidate)
  local tags = require("taskforge.tracker.tags")
  tags.process_tag(bufnr, candidate.lnum, candidate.tag, candidate.def, candidate.node)
end

-- Process a tag for manual notification (no creation)
function M.process_manual_tag(bufnr, candidate)
  -- Extract description if not already provided
  local description = candidate.description
  if not description then
    local lang = require("taskforge.lang").get_for_buffer(bufnr)
    local comment_text = vim.treesitter.get_node_text(candidate.node, bufnr)
    local info = lang.extract_tag_info(comment_text, candidate.tag)
    description = info and info.description or "No description"
  end

  -- Just notify, don't create task
  utils.notify(
    "Tag found: " .. candidate.tag .. ": " .. description .. "\nUse :TaskforgeTag add to create task",
    vim.log.levels.INFO
  )
end

-- Process tracked tags in a buffer
function M.process_tracked_tags(bufnr)
  local comment_nodes = M.find_comment_nodes(bufnr)
  local cfg = config.get().tags

  for _, node in ipairs(comment_nodes) do
    local start_row, _, end_row, _ = node:range()
    local comment_text = vim.treesitter.get_node_text(node, bufnr)

    if comment_text and #comment_text > 0 then
      -- Skip if opted out
      if comment_text:match(core.constants.optout_pattern) then
        goto continue
      end

      -- Check if this comment has a UUID (tracked)
      local uuid = comment_text:match(core.constants.uuid_pattern)
      if uuid then
        -- This is a tracked comment
        local tags = require("taskforge.tracker.tags")
        tags.process_tracked_comment(bufnr, start_row, comment_text, uuid)
      else
        -- Identify tag but don't create task during regular processing
        -- This is just for highlighting purposes
        for tag, def in pairs(cfg.definitions or {}) do
          -- Include alternative tags
          local tags_to_check = { tag }
          if def.alt then
            vim.list_extend(tags_to_check, def.alt)
          end

          -- Check for matching tag
          for _, tag_name in ipairs(tags_to_check) do
            if comment_text:match(tag_name) then
              -- Found a tag, highlight it
              M.add_tag_marker(bufnr, start_row, tag_name)
              goto continue
            end
          end
        end
      end

      ::continue::
    end
  end
end

-- Add a visual marker for a tag
function M.add_tag_marker(bufnr, lnum, tag)
  vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
    virt_text = { { "⚑ " .. tag, "Comment" } },
    virt_text_pos = "eol",
  })
end

-- Check for removed or modified tags
function M.check_removed_tags(bufnr)
  local cached_tags = core.get_all_cached_tags(bufnr)
  if not cached_tags or vim.tbl_isempty(cached_tags) then
    return
  end

  local lines = core.get_buffer_lines(bufnr, 0, -1)
  local cfg = config.get().tags

  -- Check each cached tag
  for lnum, tag_data in pairs(cached_tags) do
    -- Skip if line doesn't exist anymore
    if lnum >= #lines then
      goto continue
    end

    local line = lines[lnum + 1]

    -- Only check tags with UUIDs
    if tag_data.uuid then
      -- Check if line still exists and contains the UUID
      if not line:match(core.constants.uuid_pattern) then
        -- UUID was removed, handle based on config
        local tags = require("taskforge.tracker.tags")
        tags.handle_removed_uuid(bufnr, lnum, tag_data.uuid, tag_data.tag_def)
      elseif line:match(core.constants.uuid_pattern) ~= tag_data.uuid then
        -- UUID was changed, warn about it
        local uuid = require("taskforge.tracker.uuid")
        uuid.handle_modified_uuid(bufnr, lnum, line, tag_data.uuid)
      end
    end

    ::continue::
  end
end

-- Jump to a tag in a buffer
-- @param bufnr number Buffer number
-- @param lnum number Line number (0-indexed)
-- @return boolean Success
function M.jump_to_tag(bufnr, lnum)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  -- Check if line exists
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if lnum >= line_count then
    return false
  end

  -- Get window for buffer or open buffer in window
  local win = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == bufnr then
      win = w
      break
    end
  end

  if not win then
    -- Buffer not displayed, open it
    vim.api.nvim_set_current_buf(bufnr)
    win = vim.api.nvim_get_current_win()
  else
    -- Buffer already open, focus the window
    vim.api.nvim_set_current_win(win)
  end

  -- Jump to line
  vim.api.nvim_win_set_cursor(win, { lnum + 1, 0 })

  -- Center the line in the window
  vim.cmd("normal! zz")

  return true
end

return M

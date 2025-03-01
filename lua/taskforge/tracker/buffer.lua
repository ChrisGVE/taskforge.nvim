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
function M.process(bufnr, initial)
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

  -- If this is initial processing, find and handle all untracked tags
  if initial then
    -- Find all untracked tags in the buffer
    local untracked_tags = M.find_untracked_tags(bufnr)

    -- Process tags in batch if there are any
    if #untracked_tags > 0 then
      -- Process all tags in one go
      M.process_tag_candidates(bufnr, untracked_tags)
      return
    end
  end

  -- Regular processing - track existing tags and their changes
  M.process_tracked_tags(bufnr)

  -- Check for tag removals or modifications
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
  local comment_nodes = M.find_comment_nodes(bufnr)

  for _, node in ipairs(comment_nodes) do
    -- Extract node information
    local start_row, _, end_row, _ = node:range()
    local comment_text = vim.treesitter.get_node_text(node, bufnr)

    -- Skip if already has UUID or opted out
    if comment_text:match(core.constants.uuid_pattern) or comment_text:match(core.constants.optout_pattern) then
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
          -- Found a tag, add to candidates list
          table.insert(untracked_tags, {
            lnum = start_row,
            text = comment_text,
            tag = tag,
            def = def,
            node = node,
          })
          goto continue
        end
      end
    end

    ::continue::
  end

  return untracked_tags
end

-- Process tag candidates in batch
function M.process_tag_candidates(bufnr, candidates)
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
    M._process_auto_tag(bufnr, candidate)
  end

  -- Process manual-create tags with notification
  for _, candidate in ipairs(manual_create) do
    M._process_manual_tag(bufnr, candidate)
  end

  -- Process ask-create tags with UI
  if #ask_create > 0 then
    -- Let UI module handle this
    local ui = require("taskforge.tracker.ui")
    ui.batch_process_tags(bufnr, ask_create)
  end

  -- Provide summary if anything was processed
  if #auto_create > 0 or #manual_create > 0 then
    utils.notify(
      string.format(
        "Processed %d tags automatically, %d tags need confirmation",
        #auto_create + #manual_create,
        #ask_create
      )
    )
  end
end

-- Process a tag for auto-creation
function M._process_auto_tag(bufnr, candidate)
  local tags = require("taskforge.tracker.tags")
  tags.process_tag(bufnr, candidate.lnum, candidate.tag, candidate.def, candidate.node)
end

-- Process a tag for manual notification (no creation)
function M._process_manual_tag(bufnr, candidate)
  -- Extract description
  local lang = require("taskforge.lang").get_for_buffer(bufnr)
  local comment_text = vim.treesitter.get_node_text(candidate.node, bufnr)
  local info = lang.extract_tag_info(comment_text, candidate.tag)

  if info and info.description then
    -- Just notify, don't create task
    utils.notify(
      "Tag found: " .. candidate.tag .. ": " .. info.description .. "\nUse :TaskforgeTag add to create task",
      vim.log.levels.INFO
    )
  end
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

return M

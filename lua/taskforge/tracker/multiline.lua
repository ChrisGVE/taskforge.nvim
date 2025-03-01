-- lua/taskforge/tracker/multiline.lua
-- Multiline comment detection and handling

local M = {}
local utils = require("taskforge.utils")
local core = require("taskforge.tracker.core")
local config = require("taskforge.config")

-- Process a multiline comment
function M.process_comment_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1] - 1 -- 0-based line number

  -- Check if we're in a comment
  local context = M.detect_comment_context(bufnr, lnum)

  if not context.is_comment then
    utils.notify("Cursor is not in a comment", vim.log.levels.WARN)
    return
  end

  -- Get all lines of the comment
  local comment_lines = M.get_full_comment(bufnr, lnum)

  if not comment_lines or #comment_lines == 0 then
    utils.notify("Failed to extract comment", vim.log.levels.ERROR)
    return
  end

  -- Get configured tags
  local cfg = config.get().tags
  local available_tags = {}

  for tag, def in pairs(cfg.definitions or {}) do
    table.insert(available_tags, tag)
    if def.alt then
      for _, alt in ipairs(def.alt) do
        table.insert(available_tags, alt)
      end
    end
  end

  -- Find task tag in comment
  local tag_info = M.find_tag_in_comment(comment_lines, available_tags)

  if not tag_info then
    utils.notify("No task tag found in comment", vim.log.levels.WARN)
    return
  end

  -- Extract description
  local description = M.extract_tag_description(comment_lines, tag_info)

  -- Find tag definition
  local tag_def = nil
  for tag, def in pairs(cfg.definitions or {}) do
    if tag_info.tag == tag then
      tag_def = def
      break
    end

    -- Check alternative tags
    if def.alt then
      for _, alt in ipairs(def.alt) do
        if tag_info.tag == alt then
          tag_def = def
          break
        end
      end
    end

    if tag_def then
      break
    end
  end

  if not tag_def then
    utils.notify("No definition found for tag: " .. tag_info.tag, vim.log.levels.ERROR)
    return
  end

  -- Check if comment already has a UUID
  local has_uuid = false
  for _, line in ipairs(comment_lines) do
    if line:match(core.constants.uuid_pattern) then
      has_uuid = true
      break
    end
  end

  if has_uuid then
    utils.notify("Comment already has a task UUID", vim.log.levels.INFO)
    return
  end

  -- Check if comment has opted out
  local opted_out = false
  for _, line in ipairs(comment_lines) do
    if line:match(core.constants.optout_pattern) then
      opted_out = true
      break
    end
  end

  if opted_out then
    utils.notify("Comment has opted out from tracking", vim.log.levels.INFO)
    return
  end

  -- Create task
  local task_info = {
    description = tag_info.tag .. ": " .. description,
    file = vim.api.nvim_buf_get_name(bufnr),
    line = context.start_line + 1, -- 1-based line number
    project = require("taskforge.project").current(),
    tags = tag_def.tags,
    due = tag_def.due,
    priority = tag_def.priority,
  }

  -- Ask for confirmation based on tag definition
  if tag_def.create == "auto" then
    require("taskforge.tasks").create(task_info.description, task_info, function(uuid)
      if uuid then
        -- Link the UUID back to the comment
        M.add_uuid_to_comment(bufnr, context, uuid)
      end
    end)
  elseif tag_def.create == "ask" then
    -- Use centralized confirmation dialog
    utils.confirm_yesno("Create task for: " .. task_info.description .. "?", function(choice)
      if choice == 1 then
        require("taskforge.tasks").create(task_info.description, task_info, function(uuid)
          if uuid then
            -- Link the UUID back to the comment
            M.add_uuid_to_comment(bufnr, context, uuid)
          end
        end)
      end
    end)
  elseif tag_def.create == "manual" then
    utils.notify(
      "Tag found: " .. task_info.description .. "\nUse :TaskforgeTag add to create task",
      vim.log.levels.INFO
    )
  end
end

-- Detect if we're in a comment and what type
function M.detect_comment_context(bufnr, lnum)
  local result = {
    is_comment = false,
    multiline = false,
    start_line = nil,
    end_line = nil,
    comment_type = nil,
  }

  -- Try to use TreeSitter if available
  if vim.treesitter then
    local ok, ts_result = pcall(M._detect_with_treesitter, bufnr, lnum)
    if ok and ts_result.is_comment then
      return ts_result
    end
  end

  -- Fall back to language module
  local filetype = vim.bo[bufnr].filetype
  local lang = require("taskforge.lang").get_for_buffer(bufnr)

  -- Use language module's context detection if available
  if lang.detect_comment_context then
    return lang.detect_comment_context(bufnr, lnum)
  end

  -- Last resort: check if the line looks like a comment
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if lang.is_comment_string and lang.is_comment_string(line, filetype) then
    result.is_comment = true
    result.start_line = lnum
    result.comment_type = "line"
  end

  return result
end

-- Use treesitter for comment detection
function M._detect_with_treesitter(bufnr, lnum)
  local result = {
    is_comment = false,
    multiline = false,
    start_line = nil,
    end_line = nil,
    comment_type = nil,
  }

  -- Get parser for buffer
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return result
  end

  -- Parse buffer
  local tree = parser:parse()[1]
  if not tree then
    return result
  end

  local root = tree:root()
  if not root then
    return result
  end

  -- Get line text to determine length
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""

  -- Get node at position
  local node = root:named_descendant_for_range(lnum, 0, lnum, #line)
  if not node then
    return result
  end

  -- Walk up tree until finding comment node
  while node do
    local type = node:type()
    if type == "comment" or type == "line_comment" or type == "block_comment" then
      -- Found a comment node!
      local start_row, _, end_row, _ = node:range()

      result.is_comment = true
      result.start_line = start_row
      result.end_line = end_row
      result.multiline = (end_row > start_row)
      result.comment_type = result.multiline and "block_start" or "line"
      result.node = node

      return result
    end

    node = node:parent()
  end

  return result
end

-- Extract all lines of a comment
function M.get_full_comment(bufnr, lnum)
  local context = M.detect_comment_context(bufnr, lnum)

  if not context.is_comment then
    return nil
  end

  if not context.multiline then
    -- Single line comment
    return {
      vim.api.nvim_buf_get_lines(bufnr, context.start_line, context.start_line + 1, false)[1],
    }
  else
    -- Multiline comment
    return vim.api.nvim_buf_get_lines(bufnr, context.start_line, context.end_line + 1, false)
  end
end

-- Find task tag in comment
function M.find_tag_in_comment(comment_lines, available_tags)
  -- Prepare a pattern to match any of the available tags
  local tag_pattern = "("
  for i, tag in ipairs(available_tags) do
    if i > 1 then
      tag_pattern = tag_pattern .. "|"
    end
    tag_pattern = tag_pattern .. vim.pesc(tag)
  end
  tag_pattern = tag_pattern .. ")"

  -- Check each line for the tag
  for i, line in ipairs(comment_lines) do
    local tag = line:match(tag_pattern)
    if tag then
      return {
        tag = tag,
        line_index = i - 1, -- 0-based index
        line = line,
      }
    end
  end

  return nil
end

-- Extract description from multiline comment
function M.extract_tag_description(comment_lines, tag_info)
  local line = comment_lines[tag_info.line_index + 1] -- 1-based index
  local desc = line:match(tag_info.tag .. ":%s*(.+)")

  if not desc or desc == "" then
    -- Try different pattern
    desc = line:match(tag_info.tag .. "[^:]*:%s*(.+)")
  end

  if not desc or desc == "" then
    -- Try to get everything after the tag
    desc = line:match(tag_info.tag .. "(.+)")
  end

  -- If description is very short or not found, try to include next lines
  if not desc or #desc < 10 then
    local full_desc = desc or ""

    -- Collect lines until the end of the comment or next empty line
    for i = tag_info.line_index + 2, #comment_lines do
      local next_line = comment_lines[i]

      -- Stop at empty line or if another tag is found
      if next_line:match("^%s*$") or next_line:match("^%s*[A-Z]+:") then
        break
      end

      -- Check for comment markers at start of line
      local line_content = next_line:match("^%s*[%-#/*>]+%s*(.+)") or next_line

      -- If line content is not empty, add to description
      if line_content and line_content ~= "" then
        full_desc = full_desc .. " " .. line_content:gsub("^%s+", ""):gsub("%s+$", "")
      end
    end

    desc = full_desc
  end

  -- Clean up description
  if desc then
    desc = desc:gsub("%*/+$", ""):gsub("%s+$", ""):gsub("^%s+", "")
  else
    desc = "No description"
  end

  return desc
end

-- Add UUID to multiline comment
function M.add_uuid_to_comment(bufnr, context, uuid)
  if not context or not context.is_comment then
    return false
  end

  local filetype = vim.bo[bufnr].filetype
  local lang = require("taskforge.lang").get_for_buffer(bufnr)

  if not context.multiline then
    -- Single line comment
    local line = vim.api.nvim_buf_get_lines(bufnr, context.start_line, context.start_line + 1, false)[1]
    local new_line

    -- Use language module to add UUID if it has a method for it
    if lang.add_uuid_to_comment then
      new_line = lang.add_uuid_to_comment(line, uuid, filetype)
    else
      -- Default implementation
      new_line = line .. " [task:" .. uuid .. "]"
    end

    vim.api.nvim_buf_set_lines(bufnr, context.start_line, context.start_line + 1, false, { new_line })
    return true
  else
    -- Multiline comment
    if context.end_line then
      local end_line = vim.api.nvim_buf_get_lines(bufnr, context.end_line, context.end_line + 1, false)[1]
      local new_line

      -- Use language module if available
      if lang.add_uuid_to_multiline_comment then
        new_line = lang.add_uuid_to_multiline_comment(end_line, uuid, filetype)
      else
        -- Default implementation - try to insert before closing comment marker
        local patterns = M._get_comment_patterns(filetype)

        if patterns.block_end and end_line:match(vim.pesc(patterns.block_end)) then
          new_line = end_line:gsub(vim.pesc(patterns.block_end), " [task:" .. uuid .. "] " .. patterns.block_end)
        else
          -- No recognizable end marker, just append
          new_line = end_line .. " [task:" .. uuid .. "]"
        end
      end

      vim.api.nvim_buf_set_lines(bufnr, context.end_line, context.end_line + 1, false, { new_line })
      return true
    else
      -- No end line identified, append to the first line
      local first_line = vim.api.nvim_buf_get_lines(bufnr, context.start_line, context.start_line + 1, false)[1]
      local new_line

      if lang.add_uuid_to_comment then
        new_line = lang.add_uuid_to_comment(first_line, uuid, filetype)
      else
        new_line = first_line .. " [task:" .. uuid .. "]"
      end

      vim.api.nvim_buf_set_lines(bufnr, context.start_line, context.start_line + 1, false, { new_line })
      return true
    end
  end

  return false
end

-- Get language-specific comment patterns
function M._get_comment_patterns(filetype)
  local patterns = {
    -- Default to C-style comments
    line_start = "//",
    block_start = "/*",
    block_end = "*/",
  }

  -- Language-specific overrides
  local lang_patterns = {
    lua = {
      line_start = "--",
      block_start = "--[[",
      block_end = "]]",
    },
    python = {
      line_start = "#",
      block_start = '"""',
      block_end = '"""',
      block_start_alt = "'''",
      block_end_alt = "'''",
    },
    vim = {
      line_start = '"',
    },
    sh = {
      line_start = "#",
    },
    bash = {
      line_start = "#",
    },
    zsh = {
      line_start = "#",
    },
    ruby = {
      line_start = "#",
      block_start = "=begin",
      block_end = "=end",
    },
    html = {
      block_start = "<!--",
      block_end = "-->",
    },
    xml = {
      block_start = "<!--",
      block_end = "-->",
    },
    css = {
      block_start = "/*",
      block_end = "*/",
    },
    javascript = {
      line_start = "//",
      block_start = "/*",
      block_end = "*/",
    },
    typescript = {
      line_start = "//",
      block_start = "/*",
      block_end = "*/",
    },
  }

  -- Return specific patterns or defaults
  return lang_patterns[filetype] or patterns
end

-- Add opt-out marker to multiline comment
function M.add_optout_marker(bufnr, context)
  if not context or not context.is_comment then
    return false
  end

  local filetype = vim.bo[bufnr].filetype

  if not context.multiline then
    -- Single line comment
    local line = vim.api.nvim_buf_get_lines(bufnr, context.start_line, context.start_line + 1, false)[1]
    local new_line = line .. " [notrack]"
    vim.api.nvim_buf_set_lines(bufnr, context.start_line, context.start_line + 1, false, { new_line })
    return true
  else
    -- Multiline comment - add to end line
    if context.end_line then
      local end_line = vim.api.nvim_buf_get_lines(bufnr, context.end_line, context.end_line + 1, false)[1]
      local new_line
      local patterns = M._get_comment_patterns(filetype)

      if patterns.block_end and end_line:match(vim.pesc(patterns.block_end)) then
        new_line = end_line:gsub(vim.pesc(patterns.block_end), " [notrack] " .. patterns.block_end)
      else
        new_line = end_line .. " [notrack]"
      end

      vim.api.nvim_buf_set_lines(bufnr, context.end_line, context.end_line + 1, false, { new_line })
      return true
    else
      -- No end line, add to first line
      local first_line = vim.api.nvim_buf_get_lines(bufnr, context.start_line, context.start_line + 1, false)[1]
      local new_line = first_line .. " [notrack]"
      vim.api.nvim_buf_set_lines(bufnr, context.start_line, context.start_line + 1, false, { new_line })
      return true
    end
  end

  return false
end

return M

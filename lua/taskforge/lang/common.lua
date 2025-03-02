-- lua/taskforge/lang/common.lua
--
-- Common language patterns and fallback functionality

local M = {}

-- Module metadata
M.name = "common"
M.description = "Common language patterns for comment detection"

-- Default comment patterns for various languages
M.comment_patterns = {
  -- Default to C-style comments
  default = {
    line_start = "//",
    block_start = "/*",
    block_end = "*/",
  },

  -- Language-specific overrides
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

-- Get patterns for a specific filetype
function M.get_patterns(filetype)
  -- Return specific patterns or defaults
  return M.comment_patterns[filetype] or M.comment_patterns.default
end

-- Check if a line starts a comment
function M.is_comment_start(line, filetype)
  local patterns = M.get_patterns(filetype)

  if patterns.line_start and line:match("^%s*" .. vim.pesc(patterns.line_start)) then
    return true, "line"
  end

  if patterns.block_start and line:match("^%s*" .. vim.pesc(patterns.block_start)) then
    return true, "block_start"
  end

  if patterns.block_start_alt and line:match("^%s*" .. vim.pesc(patterns.block_start_alt)) then
    return true, "block_start_alt"
  end

  return false, nil
end

-- Check if a line ends a comment
function M.is_comment_end(line, filetype, comment_type)
  local patterns = M.get_patterns(filetype)

  if comment_type == "block_start" and patterns.block_end and line:match(vim.pesc(patterns.block_end)) then
    return true
  end

  if comment_type == "block_start_alt" and patterns.block_end_alt and line:match(vim.pesc(patterns.block_end_alt)) then
    return true
  end

  return false
end

-- Detect multiline comment context
function M.detect_comment_context(bufnr, lnum)
  local filetype = vim.bo[bufnr].filetype
  local result = {
    is_comment = false,
    multiline = false,
    start_line = nil,
    end_line = nil,
    comment_type = nil,
  }

  -- Check if treesitter is available for more accurate detection
  local has_ts, _ = pcall(require, "vim.treesitter")
  if has_ts then
    return M._detect_with_treesitter(bufnr, lnum)
  end

  -- Fallback to pattern-based detection
  local current_line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  local is_comment, comment_type = M.is_comment_start(current_line, filetype)

  if is_comment then
    result.is_comment = true
    result.start_line = lnum
    result.comment_type = comment_type

    -- If it's a block comment, find the end
    if comment_type:match("block") then
      result.multiline = true

      -- Look forward for end
      for i = lnum, vim.api.nvim_buf_line_count(bufnr) - 1 do
        local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
        if M.is_comment_end(line, filetype, comment_type) then
          result.end_line = i
          break
        end
      end
    end

    return result
  end

  -- Not a comment start, check if we're inside a multiline comment
  local patterns = M.get_patterns(filetype)
  if not patterns.block_start then
    -- Language doesn't support block comments
    return result
  end

  -- Look backward for block comment start
  for i = lnum - 1, 0, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    local is_start, start_type = M.is_comment_start(line, filetype)

    if is_start and start_type:match("block") then
      -- Found a block start, check if we're before its end
      for j = i, vim.api.nvim_buf_line_count(bufnr) - 1 do
        local check_line = vim.api.nvim_buf_get_lines(bufnr, j, j + 1, false)[1]
        if M.is_comment_end(check_line, filetype, start_type) then
          if j >= lnum then
            -- We're inside a block comment
            result.is_comment = true
            result.multiline = true
            result.start_line = i
            result.end_line = j
            result.comment_type = start_type
          end
          break
        end
      end
      break
    end
  end

  return result
end

-- Use treesitter for comment detection if available
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

      return result
    end

    node = node:parent()
  end

  return result
end

-- Extract tag and description from a comment
function M.extract_tag_info(comment_text, tag_name)
  -- Try different common formats

  -- Format 1: TAG: description
  local desc = comment_text:match(tag_name .. ":%s*(.+)")
  if desc then
    return {
      tag = tag_name,
      description = desc:gsub("%*/+$", ""):gsub("%s+$", ""):gsub("^%s+", ""),
    }
  end

  -- Format 2: TAG(meta): description
  desc = comment_text:match(tag_name .. "%([^)]*%):%s*(.+)")
  if desc then
    return {
      tag = tag_name,
      description = desc:gsub("%*/+$", ""):gsub("%s+$", ""):gsub("^%s+", ""),
    }
  end

  -- Format 3: TAG - description
  desc = comment_text:match(tag_name .. "%s*%-%s*(.+)")
  if desc then
    return {
      tag = tag_name,
      description = desc:gsub("%*/+$", ""):gsub("%s+$", ""):gsub("^%s+", ""),
    }
  end

  -- Format 4: TAG anything else
  desc = comment_text:match(tag_name .. "(.+)")
  if desc then
    -- Clean up the description
    desc = desc:gsub("^[%s:%-]+", ""):gsub("%*/+$", ""):gsub("%s+$", "")
    if desc and desc ~= "" then
      return {
        tag = tag_name,
        description = desc,
      }
    end
  end

  -- Nothing found
  return nil
end

-- Add UUID to comment text
function M.add_uuid_to_comment(comment_text, uuid, filetype)
  local patterns = M.get_patterns(filetype)
  local uuid_marker = " [task:" .. uuid .. "]"

  -- Insert before block comment end if present
  if patterns.block_end and comment_text:match(vim.pesc(patterns.block_end) .. "%s*$") then
    return comment_text:gsub(vim.pesc(patterns.block_end) .. "%s*$", uuid_marker .. " " .. patterns.block_end)
  end

  -- Otherwise just append
  return comment_text .. uuid_marker
end

-- Remove UUID from comment text
function M.remove_uuid_from_comment(comment_text)
  return comment_text:gsub("%s*%[task:[0-9a-f%-]+%]", "")
end

-- Check if a string is a comment based on syntax
function M.is_comment_string(text, filetype)
  local patterns = M.get_patterns(filetype)

  -- Check for line comment start
  if patterns.line_start and text:match("^%s*" .. vim.pesc(patterns.line_start)) then
    return true
  end

  -- Check for block comment markers
  if patterns.block_start and text:match(vim.pesc(patterns.block_start)) then
    return true
  end

  if patterns.block_end and text:match(vim.pesc(patterns.block_end)) then
    return true
  end

  return false
end

-- Add tag to comment text
function M.add_tag_to_comment(comment_text, tag, filetype)
  local patterns = M.get_patterns(filetype)

  -- Try to match the comment prefix
  local prefix_pattern = "^(%s*" .. vim.pesc(patterns.line_start) .. "%s*)"
  local prefix = comment_text:match(prefix_pattern)

  if prefix then
    -- Extract the content after the prefix
    local content = comment_text:sub(#prefix + 1)

    if content and content:len() > 0 then
      -- Add tag before existing content
      return prefix .. tag .. ": " .. content
    else
      -- Just add tag after prefix
      return prefix .. tag .. ": "
    end
  end

  -- Handle block comments
  if patterns.block_start then
    local block_prefix_pattern = "^(%s*" .. vim.pesc(patterns.block_start) .. "%s*)"
    prefix = comment_text:match(block_prefix_pattern)

    if prefix then
      local content = comment_text:sub(#prefix + 1)
      if content and content:len() > 0 then
        return prefix .. tag .. ": " .. content
      else
        return prefix .. tag .. ": "
      end
    end
  end

  -- Fallback: just append tag to the comment
  return comment_text .. " " .. tag .. ": "
end

-- Add opt-out marker to comment
function M.add_optout_marker(comment_text, filetype)
  local patterns = M.get_patterns(filetype)

  -- Insert [notrack] before block comment end if present
  if patterns.block_end and comment_text:match(vim.pesc(patterns.block_end) .. "%s*$") then
    return comment_text:gsub(vim.pesc(patterns.block_end) .. "%s*$", " [notrack] " .. patterns.block_end)
  end

  -- Otherwise just append
  return comment_text .. " [notrack]"
end

-- Get comment prefix for a language
function M.get_comment_prefix(filetype)
  local patterns = M.get_patterns(filetype)
  return patterns.line_start .. " "
end

-- Find all comment lines in a buffer (used when TreeSitter is not available)
function M.find_comment_lines(bufnr)
  local result = {}
  local filetype = vim.bo[bufnr].filetype
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for i = 0, line_count - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    if line and M.is_comment_string(line, filetype) then
      table.insert(result, { lnum = i, text = line })
    end
  end

  return result
end

return M

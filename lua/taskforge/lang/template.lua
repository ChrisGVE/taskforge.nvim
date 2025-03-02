-- lua/taskforge/lang/template.lua
--
-- Template for language-specific modules
-- Copy this file to create a new language module (e.g., python.lua, rust.lua)
-- and implement the required functions.

local M = {}

-- Module metadata (required)
M.name = "template" -- Language name
M.description = "Template language module" -- Module description
M.filetypes = { "template" } -- Filetypes this module handles

-- Comment patterns for this language (required)
-- These patterns are used for fallback detection when TreeSitter isn't available
M.comment_patterns = {
  line_start = "--", -- Line comment start marker
  line_continue = nil, -- Line continuation marker (nil if not applicable)
  block_start = "--[[", -- Block comment start marker (nil if not supported)
  block_end = "]]", -- Block comment end marker (nil if not supported)
  block_start_alt = nil, -- Alternative block start (nil if not applicable)
  block_end_alt = nil, -- Alternative block end (nil if not applicable)
}

-- Regular expressions for detecting comments (required)
M.comment_regexes = {
  line = "^%s*" .. vim.pesc(M.comment_patterns.line_start) .. "%s*(.-)%s*$", -- Line comment pattern
  block_start = M.comment_patterns.block_start
      and ("^%s*" .. vim.pesc(M.comment_patterns.block_start) .. "%s*(.-)%s*$")
    or nil, -- Block start pattern
  block_end = M.comment_patterns.block_end and ("^%s*(.-)%s*" .. vim.pesc(M.comment_patterns.block_end) .. "%s*$")
    or nil, -- Block end pattern
}

-- Check if a line is a comment (required)
-- @param line string The line to check
-- @return boolean True if the line is a comment
function M.is_comment_string(line)
  if not line then
    return false
  end

  -- Check for line comment
  if M.comment_patterns.line_start and line:match("^%s*" .. vim.pesc(M.comment_patterns.line_start)) then
    return true
  end

  -- Check for block comment
  if M.comment_patterns.block_start and line:match(vim.pesc(M.comment_patterns.block_start)) then
    return true
  end

  if M.comment_patterns.block_end and line:match(vim.pesc(M.comment_patterns.block_end)) then
    return true
  end

  return false
end

-- Extract tag information from a comment (required)
-- @param comment_text string The comment text
-- @param tag_name string The tag to extract info for
-- @return table|nil { tag = tag_name, description = description }
function M.extract_tag_info(comment_text, tag_name)
  if not comment_text or not tag_name then
    return nil
  end

  -- Try to match "TAG: description"
  local desc = comment_text:match(tag_name .. ":%s*(.+)")
  if desc then
    return {
      tag = tag_name,
      description = desc:gsub("%s+$", ""):gsub("^%s+", ""),
    }
  end

  -- Try to match "TAG(meta): description"
  desc = comment_text:match(tag_name .. "%([^)]*%):%s*(.+)")
  if desc then
    return {
      tag = tag_name,
      description = desc:gsub("%s+$", ""):gsub("^%s+", ""),
    }
  end

  -- Try to match "TAG - description"
  desc = comment_text:match(tag_name .. "%s*%-%s*(.+)")
  if desc then
    return {
      tag = tag_name,
      description = desc:gsub("%s+$", ""):gsub("^%s+", ""),
    }
  end

  -- Try anything after the tag
  desc = comment_text:match(tag_name .. "(.+)")
  if desc then
    -- Clean up the description
    desc = desc:gsub("^[%s:%-]+", ""):gsub("%s+$", "")
    if desc and desc ~= "" then
      return {
        tag = tag_name,
        description = desc,
      }
    end
  end

  return nil
end

-- Detect if we're in a comment and what type (required)
-- @param bufnr number Buffer number
-- @param lnum number Line number (0-based)
-- @return table { is_comment = boolean, multiline = boolean, start_line = number, end_line = number, comment_type = string }
function M.detect_comment_context(bufnr, lnum)
  local result = {
    is_comment = false,
    multiline = false,
    start_line = nil,
    end_line = nil,
    comment_type = nil,
  }

  -- Try to use TreeSitter first if available
  if vim.treesitter then
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if ok and parser then
      local tree = parser:parse()[1]
      if tree then
        local root = tree:root()
        if root then
          -- Get line text to determine length
          local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""

          -- Get node at position
          local node = root:named_descendant_for_range(lnum, 0, lnum, #line)
          if node then
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
          end
        end
      end
    end
  end

  -- Fallback to pattern matching
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if not line then
    return result
  end

  -- Check if line is a comment start
  local is_comment, comment_type = M.is_comment_start(line)

  if is_comment then
    result.is_comment = true
    result.start_line = lnum
    result.comment_type = comment_type

    -- If block comment, find the end
    if comment_type:match("block") then
      result.multiline = true

      -- Look forward for end
      for i = lnum, vim.api.nvim_buf_line_count(bufnr) - 1 do
        local check_line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
        if M.is_comment_end(check_line, comment_type) then
          result.end_line = i
          break
        end
      end
    end
  else
    -- Check if we're inside a block comment by looking backward
    for i = lnum - 1, math.max(0, lnum - 50), -1 do
      local check_line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
      if not check_line then
        break
      end

      local check_is_start, check_type = M.is_comment_start(check_line)
      if check_is_start and check_type:match("block") then
        -- Found a block start, check if our line is before the end
        local found_end = false
        for j = i + 1, math.min(vim.api.nvim_buf_line_count(bufnr) - 1, i + 50) do
          local end_check_line = vim.api.nvim_buf_get_lines(bufnr, j, j + 1, false)[1]
          if M.is_comment_end(end_check_line, check_type) then
            found_end = true
            if j >= lnum then
              -- We're inside a block comment
              result.is_comment = true
              result.multiline = true
              result.start_line = i
              result.end_line = j
              result.comment_type = check_type
            end
            break
          end
        end

        if found_end or result.is_comment then
          -- Either we found the end or we're in a comment
          break
        end
      end
    end
  end

  return result
end

-- Check if a line starts a comment
-- @param line string The line to check
-- @return boolean, string is_comment_start, comment_type
function M.is_comment_start(line)
  if not line then
    return false, nil
  end

  if M.comment_patterns.line_start and line:match("^%s*" .. vim.pesc(M.comment_patterns.line_start)) then
    return true, "line"
  end

  if M.comment_patterns.block_start and line:match("^%s*" .. vim.pesc(M.comment_patterns.block_start)) then
    return true, "block_start"
  end

  if M.comment_patterns.block_start_alt and line:match("^%s*" .. vim.pesc(M.comment_patterns.block_start_alt)) then
    return true, "block_start_alt"
  end

  return false, nil
end

-- Check if a line ends a comment
-- @param line string The line to check
-- @param comment_type string The type of comment
-- @return boolean is_comment_end
function M.is_comment_end(line, comment_type)
  if not line or not comment_type then
    return false
  end

  if
    comment_type == "block_start"
    and M.comment_patterns.block_end
    and line:match(vim.pesc(M.comment_patterns.block_end))
  then
    return true
  end

  if
    comment_type == "block_start_alt"
    and M.comment_patterns.block_end_alt
    and line:match(vim.pesc(M.comment_patterns.block_end_alt))
  then
    return true
  end

  return false
end

-- Add UUID to comment text (required)
-- @param comment_text string Comment text
-- @param uuid string UUID to add
-- @param filetype string File type
-- @return string Updated comment text
function M.add_uuid_to_comment(comment_text, uuid, filetype)
  local uuid_marker = " [task:" .. uuid .. "]"

  -- Insert before block comment end if present
  if M.comment_patterns.block_end and comment_text:match(vim.pesc(M.comment_patterns.block_end) .. "%s*$") then
    return comment_text:gsub(
      vim.pesc(M.comment_patterns.block_end) .. "%s*$",
      uuid_marker .. " " .. M.comment_patterns.block_end
    )
  end

  -- Otherwise just append
  return comment_text .. uuid_marker
end

-- Add tag to comment text (required)
-- @param comment_text string Comment text
-- @param tag string Tag to add
-- @param filetype string File type
-- @return string Updated comment text
function M.add_tag_to_comment(comment_text, tag, filetype)
  -- Check if the comment already has content
  local content_pattern = "^(%s*" .. vim.pesc(M.comment_patterns.line_start) .. "%s*)(.*)$"
  local prefix, content = comment_text:match(content_pattern)

  if prefix then
    if content and content:len() > 0 then
      -- Comment has content, prepend tag
      return prefix .. tag .. ": " .. content
    else
      -- Empty comment, just add tag
      return prefix .. tag .. ": "
    end
  end

  -- Couldn't match pattern, just return original with tag appended
  return comment_text .. " " .. tag .. ": "
end

-- Add opt-out marker to comment (required)
-- @param comment_text string Comment text
-- @param filetype string File type
-- @return string Updated comment text
function M.add_optout_marker(comment_text, filetype)
  -- Insert [notrack] before block comment end if present
  if M.comment_patterns.block_end and comment_text:match(vim.pesc(M.comment_patterns.block_end) .. "%s*$") then
    return comment_text:gsub(
      vim.pesc(M.comment_patterns.block_end) .. "%s*$",
      " [notrack] " .. M.comment_patterns.block_end
    )
  end

  -- Otherwise just append
  return comment_text .. " [notrack]"
end

-- Get comment prefix for a language
-- @param filetype string File type
-- @return string Comment prefix
function M.get_comment_prefix(filetype)
  return M.comment_patterns.line_start .. " "
end

-- Find all comment lines in a buffer (used when TreeSitter is not available)
-- @param bufnr number Buffer number
-- @return table Array of { lnum = number, text = string }
function M.find_comment_lines(bufnr)
  local result = {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for i = 0, line_count - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    if line and M.is_comment_string(line) then
      table.insert(result, { lnum = i, text = line })
    end
  end

  return result
end

return M

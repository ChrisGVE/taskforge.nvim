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

  -- Language-specific pattern definitions moved to their own modules
  -- Only keeping this as a reference table
}

-- Helper function to escape pattern special characters
function M.escape_pattern(text)
  return text:gsub("[%%%(%)%.%[%]%*%+%-%?%^%$]", "%%%1")
end

-- Get patterns for a specific filetype from the common patterns
function M.get_patterns(filetype)
  -- Return specific patterns or defaults
  return M.comment_patterns[filetype] or M.comment_patterns.default
end

-- Extract common patterns from a comment line
function M.extract_common_patterns(line, patterns)
  -- Basic pattern for finding comment markers
  local markers = {}

  if patterns.line_start and line:match("^%s*" .. M.escape_pattern(patterns.line_start)) then
    table.insert(markers, {
      type = "line",
      start = line:find(M.escape_pattern(patterns.line_start)),
      pattern = patterns.line_start,
    })
  end

  if patterns.block_start and line:match(M.escape_pattern(patterns.block_start)) then
    table.insert(markers, {
      type = "block_start",
      start = line:find(M.escape_pattern(patterns.block_start)),
      pattern = patterns.block_start,
    })
  end

  if patterns.block_end and line:match(M.escape_pattern(patterns.block_end)) then
    table.insert(markers, {
      type = "block_end",
      start = line:find(M.escape_pattern(patterns.block_end)),
      pattern = patterns.block_end,
    })
  end

  return markers
end

-- Common function for checking if text is a comment string
-- This is a fallback when language-specific methods aren't available
function M.is_comment_string(line, filetype)
  if not line then
    return false
  end

  local patterns = M.get_patterns(filetype)

  -- Check for line comment
  if patterns.line_start and line:match("^%s*" .. M.escape_pattern(patterns.line_start)) then
    return true
  end

  -- Check for block comment markers
  if patterns.block_start and line:match(M.escape_pattern(patterns.block_start)) then
    return true
  end

  if patterns.block_end and line:match(M.escape_pattern(patterns.block_end)) then
    return true
  end

  return false
end

-- Common pattern for extracting tag info from a comment
-- Can be extended by language-specific implementations
function M.extract_tag_info(comment_text, tag_name)
  if not comment_text or not tag_name then
    return nil
  end

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

-- Basic implementation of UUID addition to a comment
-- Language modules should override this with language-specific formatting
function M.add_uuid_to_comment(comment_text, uuid, filetype)
  local patterns = M.get_patterns(filetype)
  local uuid_marker = " [task:" .. uuid .. "]"

  -- Insert before block comment end if present
  if patterns.block_end and comment_text:match(M.escape_pattern(patterns.block_end) .. "%s*$") then
    return comment_text:gsub(M.escape_pattern(patterns.block_end) .. "%s*$", uuid_marker .. " " .. patterns.block_end)
  end

  -- Otherwise just append
  return comment_text .. uuid_marker
end

-- Remove UUID from a comment
function M.remove_uuid_from_comment(comment_text)
  return comment_text:gsub("%s*%[task:[0-9a-f%-]+%]", "")
end

-- Base implementation of tag addition to a comment
function M.add_tag_to_comment(comment_text, tag, filetype)
  local patterns = M.get_patterns(filetype)

  -- Try to match the comment prefix
  local prefix_pattern = "^(%s*" .. M.escape_pattern(patterns.line_start) .. "%s*)"
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
    local block_prefix_pattern = "^(%s*" .. M.escape_pattern(patterns.block_start) .. "%s*)"
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

-- Common implementation for adding opt-out marker
function M.add_optout_marker(comment_text, filetype)
  local patterns = M.get_patterns(filetype)

  -- Insert [notrack] before block comment end if present
  if patterns.block_end and comment_text:match(M.escape_pattern(patterns.block_end) .. "%s*$") then
    return comment_text:gsub(M.escape_pattern(patterns.block_end) .. "%s*$", " [notrack] " .. patterns.block_end)
  end

  -- Otherwise just append
  return comment_text .. " [notrack]"
end

-- Basic comment prefix detection
function M.get_comment_prefix(filetype)
  local patterns = M.get_patterns(filetype)
  return patterns.line_start .. " "
end

return M

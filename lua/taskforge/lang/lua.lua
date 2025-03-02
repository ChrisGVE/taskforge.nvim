-- lua/taskforge/lang/lua.lua
--
-- Lua-specific language module for comment detection and handling

local M = {}

-- Module metadata
M.name = "lua"
M.description = "Lua language module for taskforge"
M.filetypes = { "lua" }

-- Lua comment patterns
M.comment_patterns = {
  line_start = "--", -- Line comment marker
  line_continue = nil, -- Lua doesn't have line continuation
  block_start = "--[[", -- Block comment start
  block_end = "]]", -- Block comment end
  block_start_alt = "--[=[", -- Alternative block comment start
  block_end_alt = "]=]", -- Alternative block comment end
}

-- Regex patterns for comments
M.comment_regexes = {
  line = "^%s*" .. vim.pesc(M.comment_patterns.line_start) .. "%s*(.-)%s*$",
  block_start = "^%s*" .. vim.pesc(M.comment_patterns.block_start) .. "%s*(.-)%s*$",
  block_end = "^%s*(.-)%s*" .. vim.pesc(M.comment_patterns.block_end) .. "%s*$",
  -- Also support alternative block comment syntax
  block_start_alt = "^%s*" .. vim.pesc(M.comment_patterns.block_start_alt) .. "%s*(.-)%s*$",
  block_end_alt = "^%s*(.-)%s*" .. vim.pesc(M.comment_patterns.block_end_alt) .. "%s*$",
}

-- Check if a string is a Lua comment
function M.is_comment_string(line)
  if not line then
    return false
  end

  -- Check for single line comment
  if line:match("^%s*" .. vim.pesc(M.comment_patterns.line_start)) then
    return true
  end

  -- Check for block comment markers
  if
    line:match(vim.pesc(M.comment_patterns.block_start))
    or line:match(vim.pesc(M.comment_patterns.block_end))
    or line:match(vim.pesc(M.comment_patterns.block_start_alt))
    or line:match(vim.pesc(M.comment_patterns.block_end_alt))
  then
    return true
  end

  return false
end

-- Extract tag information from a Lua comment
function M.extract_tag_info(comment_text, tag_name)
  if not comment_text or not tag_name then
    return nil
  end

  -- Try different formats
  -- Format 1: "-- TODO: Implement feature"
  local desc = comment_text:match(tag_name .. ":%s*(.+)")
  if desc then
    return {
      tag = tag_name,
      description = desc:gsub("%s+$", ""):gsub("^%s+", ""),
    }
  end

  -- Format 2: "-- TODO(high): Implement feature"
  desc = comment_text:match(tag_name .. "%([^)]*%):%s*(.+)")
  if desc then
    return {
      tag = tag_name,
      description = desc:gsub("%s+$", ""):gsub("^%s+", ""),
    }
  end

  -- Format 3: "-- TODO - Implement feature"
  desc = comment_text:match(tag_name .. "%s*%-%s*(.+)")
  if desc then
    return {
      tag = tag_name,
      description = desc:gsub("%s+$", ""):gsub("^%s+", ""),
    }
  end

  -- Format 4: "-- TODO Implement feature"
  desc = comment_text:match(tag_name .. "([^:].+)")
  if desc then
    desc = desc:gsub("^%s+", ""):gsub("%s+$", "")
    if desc and desc ~= "" then
      return {
        tag = tag_name,
        description = desc,
      }
    end
  end

  return nil
end

-- Check if a line is a comment start
function M.is_comment_start(line)
  if not line then
    return false, nil
  end

  if line:match("^%s*" .. vim.pesc(M.comment_patterns.line_start)) then
    return true, "line"
  end

  if line:match("^%s*" .. vim.pesc(M.comment_patterns.block_start)) then
    return true, "block_start"
  end

  if line:match("^%s*" .. vim.pesc(M.comment_patterns.block_start_alt)) then
    return true, "block_start_alt"
  end

  return false, nil
end

-- Check if a line is a comment end
function M.is_comment_end(line, comment_type)
  if not line or not comment_type then
    return false
  end

  if comment_type == "block_start" and line:match(vim.pesc(M.comment_patterns.block_end)) then
    return true
  end

  if comment_type == "block_start_alt" and line:match(vim.pesc(M.comment_patterns.block_end_alt)) then
    return true
  end

  return false
end

-- Detect if we're in a Lua comment and what type
function M.detect_comment_context(bufnr, lnum)
  -- Use the common implementation from template with specific Lua patterns
  local common = require("taskforge.lang.common")
  local context = common.detect_comment_context(bufnr, lnum)

  -- For Lua, we need to handle special cases like multi-level block comments
  if not context.is_comment then
    -- Check for multi-level block comments like --[==[ ... ]==]
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
    if line then
      -- Check for any level block comment (more general pattern)
      if line:match("^%s*%-%-[%[=]+") then
        context.is_comment = true
        context.start_line = lnum
        context.comment_type = "block_custom"
        context.multiline = true

        -- Find matching end
        local level_pattern = line:match("^%s*%-%-([%[=]+)")
        if level_pattern then
          local end_pattern = level_pattern:gsub("%[", "]")
          for i = lnum, vim.api.nvim_buf_line_count(bufnr) - 1 do
            local check_line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
            if check_line and check_line:match(vim.pesc(end_pattern)) then
              context.end_line = i
              break
            end
          end
        end
      end
    end
  end

  return context
end

-- Add UUID to Lua comment
function M.add_uuid_to_comment(comment_text, uuid, filetype)
  local uuid_marker = " [task:" .. uuid .. "]"

  -- Handle block comment endings specially for Lua
  if comment_text:match("]]%s*$") then
    return comment_text:gsub("]]%s*$", uuid_marker .. " ]]")
  elseif comment_text:match("]=]%s*$") then
    return comment_text:gsub("]=]%s*$", uuid_marker .. " ]=]")
  elseif comment_text:match("]===+]%s*$") then
    -- Handle any level of equals signs
    local closing = comment_text:match("(]===+])%s*$")
    if closing then
      return comment_text:gsub(vim.pesc(closing) .. "%s*$", uuid_marker .. " " .. closing)
    end
  end

  -- For line comments or other cases, just append
  return comment_text .. uuid_marker
end

-- Add tag to Lua comment text
function M.add_tag_to_comment(comment_text, tag, filetype)
  -- Lua-specific implementation of adding a tag to a comment
  local comment_prefix = "^(%s*%--%s*)"
  local prefix = comment_text:match(comment_prefix)

  if prefix then
    -- Extract content after the comment marker
    local content = comment_text:sub(#prefix + 1)

    if content and content:len() > 0 then
      -- Comment has content, format with tag
      return prefix .. tag .. ": " .. content
    else
      -- Empty comment, just add tag
      return prefix .. tag .. ": "
    end
  end

  -- Check for block comment
  local block_prefix = "^(%s*%-%-[%[=]+%s*)"
  prefix = comment_text:match(block_prefix)

  if prefix then
    -- Block comment start
    local content = comment_text:sub(#prefix + 1)

    if content and content:len() > 0 then
      return prefix .. tag .. ": " .. content
    else
      return prefix .. tag .. ": "
    end
  end

  -- If we get here, we couldn't properly parse the comment
  -- Just prepend the tag to the content
  return comment_text:gsub("^(%s*%-%-.*)$", "%1 " .. tag .. ": ")
end

-- Add opt-out marker to Lua comment
function M.add_optout_marker(comment_text, filetype)
  -- Handle block comment endings specially for Lua
  if comment_text:match("]]%s*$") then
    return comment_text:gsub("]]%s*$", " [notrack] ]]")
  elseif comment_text:match("]=]%s*$") then
    return comment_text:gsub("]=]%s*$", " [notrack] ]=]")
  elseif comment_text:match("]===+]%s*$") then
    -- Handle any level of equals signs
    local closing = comment_text:match("(]===+])%s*$")
    if closing then
      return comment_text:gsub(vim.pesc(closing) .. "%s*$", " [notrack] " .. closing)
    end
  end

  -- For line comments or other cases, just append
  return comment_text .. " [notrack]"
end

-- Get Lua comment prefix
function M.get_comment_prefix(filetype)
  return "-- "
end

return M

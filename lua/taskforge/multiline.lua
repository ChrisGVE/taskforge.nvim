-- lua/taskforge/multiline.lua
-- Improved comment detection for multiline comments
local M = {}

-- Get language-specific patterns
local function get_language_patterns(filetype)
  local patterns = {
    -- Default (C-style) comment patterns
    line_start = "//",
    block_start = "/*",
    block_end = "*/",
    line_continue = nil,
  }

  -- Language-specific overrides
  local lang_patterns = {
    lua = {
      line_start = "--",
      block_start = "--[[",
      block_end = "]]",
      line_continue = nil,
    },
    python = {
      line_start = "#",
      block_start = '"""',
      block_end = '"""',
      block_start_alt = "'''",
      block_end_alt = "'''",
      line_continue = nil,
    },
    vim = {
      line_start = '"',
      line_continue = nil,
    },
    bash = {
      line_start = "#",
      line_continue = nil,
    },
    sh = {
      line_start = "#",
      line_continue = nil,
    },
    zsh = {
      line_start = "#",
      line_continue = nil,
    },
    ruby = {
      line_start = "#",
      block_start = "=begin",
      block_end = "=end",
      line_continue = nil,
    },
    html = {
      block_start = "<!--",
      block_end = "-->",
      line_continue = nil,
    },
    xml = {
      block_start = "<!--",
      block_end = "-->",
      line_continue = nil,
    },
    markdown = {
      line_start = nil,
      block_start = "<!--",
      block_end = "-->",
      line_continue = nil,
    },
  }

  -- Return language-specific patterns or defaults
  return lang_patterns[filetype] or patterns
end

-- Check if a line is a comment start
function M.is_comment_start(line, filetype)
  local patterns = get_language_patterns(filetype)

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

-- Check if a line is a comment end
function M.is_comment_end(line, filetype, comment_type)
  local patterns = get_language_patterns(filetype)

  if comment_type == "block_start" and patterns.block_end and line:match(vim.pesc(patterns.block_end)) then
    return true
  end

  if comment_type == "block_start_alt" and patterns.block_end_alt and line:match(vim.pesc(patterns.block_end_alt)) then
    return true
  end

  return false
end

-- Detect if we're in a comment and what type
function M.detect_comment_context(bufnr, lnum)
  local filetype = vim.bo[bufnr].filetype
  local patterns = get_language_patterns(filetype)
  local result = {
    is_comment = false,
    multiline = false,
    start_line = nil,
    end_line = nil,
    comment_type = nil,
  }

  -- Check current line first
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

  -- If not a comment start, check if we're inside a multiline comment
  -- Look backward for block comment start
  local in_block = false
  local block_start_line = nil
  local block_type = nil

  for i = lnum - 1, 0, -1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    local is_start, start_type = M.is_comment_start(line, filetype)

    if is_start and start_type:match("block") then
      in_block = true
      block_start_line = i
      block_type = start_type
      break
    end

    -- If we find a block end before a start, we're not in a block
    if
      (patterns.block_end and line:match(vim.pesc(patterns.block_end)))
      or (patterns.block_end_alt and line:match(vim.pesc(patterns.block_end_alt)))
    then
      break
    end
  end

  if in_block then
    -- Now check if current line is before the end
    for i = block_start_line, vim.api.nvim_buf_line_count(bufnr) - 1 do
      local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]

      if i > lnum and M.is_comment_end(line, filetype, block_type) then
        result.is_comment = true
        result.multiline = true
        result.start_line = block_start_line
        result.end_line = i
        result.comment_type = block_type
        break
      end

      if i == lnum and M.is_comment_end(line, filetype, block_type) then
        result.is_comment = true
        result.multiline = true
        result.start_line = block_start_line
        result.end_line = i
        result.comment_type = block_type
        break
      end
    end
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
  local patterns = get_language_patterns(filetype)

  if not context.multiline then
    -- Single line comment
    local line = vim.api.nvim_buf_get_lines(bufnr, context.start_line, context.start_line + 1, false)[1]
    local new_line = line .. " [task:" .. uuid .. "]"
    vim.api.nvim_buf_set_lines(bufnr, context.start_line, context.start_line + 1, false, { new_line })
    return true
  else
    -- Multiline comment
    if context.end_line then
      local end_line = vim.api.nvim_buf_get_lines(bufnr, context.end_line, context.end_line + 1, false)[1]

      -- Insert UUID before the closing comment marker
      local new_line
      if patterns.block_end and end_line:match(vim.pesc(patterns.block_end)) then
        new_line = end_line:gsub(vim.pesc(patterns.block_end), " [task:" .. uuid .. "] " .. patterns.block_end)
      elseif patterns.block_end_alt and end_line:match(vim.pesc(patterns.block_end_alt)) then
        new_line = end_line:gsub(vim.pesc(patterns.block_end_alt), " [task:" .. uuid .. "] " .. patterns.block_end_alt)
      else
        -- End marker not found on the last line, just append
        new_line = end_line .. " [task:" .. uuid .. "]"
      end

      vim.api.nvim_buf_set_lines(bufnr, context.end_line, context.end_line + 1, false, { new_line })
      return true
    else
      -- No end line found, append to the first line
      local first_line = vim.api.nvim_buf_get_lines(bufnr, context.start_line, context.start_line + 1, false)[1]
      local new_line = first_line .. " [task:" .. uuid .. "]"
      vim.api.nvim_buf_set_lines(bufnr, context.start_line, context.start_line + 1, false, { new_line })
      return true
    end
  end

  return false
end

-- Main entry point to handle multiline comment tags
function M.process_comment_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1] - 1 -- 0-based line number

  -- Check if we're in a comment
  local context = M.detect_comment_context(bufnr, lnum)

  if not context.is_comment then
    vim.notify("Cursor is not in a comment", vim.log.levels.WARN)
    return
  end

  -- Get all lines of the comment
  local comment_lines = M.get_full_comment(bufnr, lnum)

  if not comment_lines or #comment_lines == 0 then
    vim.notify("Failed to extract comment", vim.log.levels.ERROR)
    return
  end

  -- Get configured tags
  local cfg = require("taskforge.config").get()
  local available_tags = {}

  for tag, def in pairs(cfg.tags.definitions or {}) do
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
    vim.notify("No task tag found in comment", vim.log.levels.WARN)
    return
  end

  -- Extract description
  local description = M.extract_tag_description(comment_lines, tag_info)

  -- Find tag definition
  local tag_def = nil
  for tag, def in pairs(cfg.tags.definitions or {}) do
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
    vim.notify("No definition found for tag: " .. tag_info.tag, vim.log.levels.ERROR)
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
    require("taskforge.utils").confirm_yesno("Create task for: " .. task_info.description .. "?", function(choice)
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
    require("taskforge.utils").notify(
      "Tag found: " .. task_info.description .. "\nUse :TaskforgeTag add to create task",
      vim.log.levels.INFO
    )
  end
end

return M

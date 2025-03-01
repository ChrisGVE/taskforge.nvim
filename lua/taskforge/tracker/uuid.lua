-- lua/taskforge/tracker/uuid.lua
-- UUID handling and protection

local M = {}
local core = require("taskforge.tracker.core")
local utils = require("taskforge.utils")

-- Constants
M.constants = {
  -- UUID pattern for task identification in comments
  uuid_pattern = "%[task:([0-9a-f%-]+)%]",
  -- Format for UUID marker
  uuid_format = "[task:%s]",
}

-- Handle a modified UUID in a comment
function M.handle_modified_uuid(bufnr, lnum, line, original_uuid)
  local current_uuid = line:match(M.constants.uuid_pattern)

  utils.debug_log("UUID", "UUID modified", {
    original = original_uuid,
    current = current_uuid,
    line_num = lnum + 1,
  })

  -- Skip if we're currently editing
  local tracker = require("taskforge.tracker")
  if tracker.state.edit_active then
    return
  end

  -- Ask user if they want to restore the UUID
  utils.confirm_yesno(
    "Task reference (UUID) was modified, which could break task tracking. Restore original format?",
    function(choice)
      if choice == 1 then
        M.restore_uuid(bufnr, lnum, line, original_uuid)
      end
    end
  )
end

-- Restore a UUID to its original format
function M.restore_uuid(bufnr, lnum, line, uuid)
  -- Create the correct format
  local original_marker = string.format(M.constants.uuid_format, uuid)

  -- Replace any existing UUID with the original
  local new_line
  if line:match(M.constants.uuid_pattern) then
    new_line = line:gsub("%[task:[0-9a-f%-]+%]", original_marker)
  else
    -- No UUID exists, add it
    new_line = M.add_uuid_to_line(line, uuid)
  end

  -- Update the line
  vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
  utils.notify("Task reference restored", vim.log.levels.INFO)
end

-- Add a UUID to a comment line
function M.add_uuid_to_line(line, uuid)
  local ft = vim.bo.filetype
  local lang = require("taskforge.lang").get_for_buffer()

  -- Use language module to add UUID properly
  return lang.add_uuid_to_comment(line, uuid, ft)
end

-- Link a UUID to a comment
function M.link_uuid_to_comment(bufnr, lnum, uuid)
  -- Check if buffer and line are valid
  if not vim.api.nvim_buf_is_valid(bufnr) then
    utils.debug_log("UUID", "Buffer no longer valid", bufnr)
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if lnum >= line_count then
    utils.debug_log("UUID", "Line no longer exists", lnum)
    return false
  end

  -- Get current line
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]

  -- Check if UUID already exists
  if line:match(M.constants.uuid_pattern) then
    utils.debug_log("UUID", "UUID already exists in line", uuid)
    return false
  end

  -- Try to use language module for proper placement
  local ft = vim.bo[bufnr].filetype
  local lang = require("taskforge.lang").get_for_buffer(bufnr)

  -- Get comment context
  local context = lang.detect_comment_context(bufnr, lnum)
  if context.is_comment then
    -- Add UUID to appropriate part of comment
    local success = false

    if context.multiline then
      -- Get all lines of the comment
      local start_line = context.start_line
      local end_line = context.end_line or start_line

      -- For multiline comments, add to the end line
      local end_line_text = vim.api.nvim_buf_get_lines(bufnr, end_line, end_line + 1, false)[1]
      local new_line = lang.add_uuid_to_comment(end_line_text, uuid, ft)
      vim.api.nvim_buf_set_lines(bufnr, end_line, end_line + 1, false, { new_line })
      success = true
    else
      -- Single line comment
      local new_line = lang.add_uuid_to_comment(line, uuid, ft)
      vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
      success = true
    end

    if success then
      -- Update task location in cache
      core.update_task_location(uuid, vim.api.nvim_buf_get_name(bufnr), lnum + 1)
      utils.debug_log("UUID", "Successfully linked UUID to comment", uuid)
      return true
    end
  end

  -- Fallback: just append to the current line
  local new_line = line .. " [task:" .. uuid .. "]"
  vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

  -- Update task location in cache
  core.update_task_location(uuid, vim.api.nvim_buf_get_name(bufnr), lnum + 1)
  utils.debug_log("UUID", "Linked UUID to comment (fallback method)", uuid)

  return true
end

-- Remove UUID from a comment
function M.remove_uuid_from_comment(bufnr, lnum, uuid)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]

  -- Check if line has this UUID
  if not line:match(core.escape_pattern("[task:" .. uuid .. "]")) then
    return false
  end

  -- Remove UUID marker
  local new_line = line:gsub("%s*%[task:" .. uuid .. "%]", "")
  vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

  return true
end

-- Extract all UUIDs from a buffer
function M.extract_all_uuids(bufnr)
  local uuids = {}
  local lines = core.get_buffer_lines(bufnr, 0, -1)

  for i, line in ipairs(lines) do
    local uuid = line:match(M.constants.uuid_pattern)
    if uuid then
      table.insert(uuids, {
        uuid = uuid,
        lnum = i - 1, -- Convert to 0-based line number
      })
    end
  end

  return uuids
end

-- Check a buffer for potentially broken UUID references after formatting
function M.check_after_formatting(bufnr)
  local uuids_to_check = core.get_uuids_for_file(vim.api.nvim_buf_get_name(bufnr))

  if #uuids_to_check == 0 then
    return
  end

  local lines = core.get_buffer_lines(bufnr, 0, -1)
  local fixed_count = 0

  for _, uuid in ipairs(uuids_to_check) do
    local found = false
    local needs_fix = false

    for i, line in ipairs(lines) do
      -- Check if line has a valid UUID marker
      local exact_uuid = line:match(M.constants.uuid_pattern)
      if exact_uuid and exact_uuid == uuid then
        found = true
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
          new_line = M.add_uuid_to_line(line, uuid)
        end

        vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { new_line })
        fixed_count = fixed_count + 1
        break
      end
    end
  end

  if fixed_count > 0 then
    utils.notify("Fixed " .. fixed_count .. " task references after formatting", vim.log.levels.INFO)
  end

  return fixed_count
end

return M

-- lua/taskforge/tracker/formatter.lua
-- Formatter compatibility and integration

local M = {}
local utils = require("taskforge.utils")
local core = require("taskforge.tracker.core")
local config = require("taskforge.config")

-- Setup formatter integration
function M.setup()
  -- Set up autocommands for formatter integration
  M._setup_formatter_hooks()
end

-- Set up hooks for popular formatters
function M._setup_formatter_hooks()
  -- Try to hook into common formatters
  vim.api.nvim_create_autocmd("User", {
    pattern = { "FormatPre", "FormatPost", "ConformPre", "ConformPost" },
    callback = function(evt)
      if evt.match == "FormatPre" or evt.match == "ConformPre" then
        -- Optionally store pre-format state
        M._handle_pre_format(evt.buf)
      elseif evt.match == "FormatPost" or evt.match == "ConformPost" then
        -- Fix any formatting issues
        M._handle_post_format(evt.buf)
      end
    end,
  })

  -- Try to detect null-ls formatter
  local has_null_ls = pcall(require, "null-ls")
  if has_null_ls then
    vim.api.nvim_create_autocmd("User", {
      pattern = { "NullLsFormatPre", "NullLsFormatPost" },
      callback = function(evt)
        if evt.match == "NullLsFormatPre" then
          M._handle_pre_format(evt.buf)
        elseif evt.match == "NullLsFormatPost" then
          M._handle_post_format(evt.buf)
        end
      end,
    })
  end

  -- Try to detect LSP format operation through BufWritePre/Post
  vim.api.nvim_create_autocmd({ "BufWritePre" }, {
    callback = function(evt)
      local bufnr = evt.buf
      -- Check if this buffer has LSP formatters
      local has_formatter = false
      for _, client in ipairs(vim.lsp.get_active_clients({ bufnr = bufnr })) do
        if client.server_capabilities.documentFormattingProvider then
          has_formatter = true
          break
        end
      end

      if has_formatter then
        M._handle_pre_format(bufnr)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    callback = function(evt)
      local bufnr = evt.buf
      -- Process buffer after a short delay to ensure formatting is complete
      vim.defer_fn(function()
        M._handle_post_format(bufnr)
      end, 100)
    end,
  })
end

-- Handle pre-format operation
function M._handle_pre_format(bufnr)
  -- Store the pre-format state
  M._save_tag_state(bufnr)
end

-- Handle post-format operation
function M._handle_post_format(bufnr)
  -- Fix any UUIDs that may have been damaged by formatting
  M._repair_uuids(bufnr)
end

-- Save the current state of tags before formatting
function M._save_tag_state(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Save a snapshot of tagged lines
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local uuids = {}

  for uuid, location in pairs(core.state.task_cache) do
    if location.file == file_path then
      table.insert(uuids, {
        uuid = uuid,
        line = location.line,
        expected_format = "[task:" .. uuid .. "]",
      })
    end
  end

  -- Store in buffer local variable
  vim.api.nvim_buf_set_var(bufnr, "taskforge_tags_pre_format", uuids)
  utils.debug_log("FORMATTER", "Saved pre-format state", #uuids)
end

-- Repair UUIDs that may have been broken by formatting
function M._repair_uuids(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Check if we have pre-format state
  local has_state, uuids = pcall(vim.api.nvim_buf_get_var, bufnr, "taskforge_tags_pre_format")
  if has_state and uuids and #uuids > 0 then
    utils.debug_log("FORMATTER", "Checking UUIDs after formatting", #uuids)
  else
    -- No pre-format state, try to repair based on file path
    uuids = {}
    local file_path = vim.api.nvim_buf_get_name(bufnr)

    for uuid, location in pairs(core.state.task_cache) do
      if location.file == file_path then
        table.insert(uuids, {
          uuid = uuid,
          line = location.line,
          expected_format = "[task:" .. uuid .. "]",
        })
      end
    end
  end

  if #uuids == 0 then
    return
  end

  local lines = core.get_buffer_lines(bufnr, 0, -1)
  local fixed_count = 0

  -- Strategy 1: Check exact lines where UUIDs were previously
  for _, info in ipairs(uuids) do
    local line_idx = info.line - 1 -- Convert to 0-based
    if line_idx < #lines then
      local line = lines[line_idx + 1]
      -- Check if UUID exists but in wrong format
      if not line:match(core.constants.uuid_pattern) and line:match(info.uuid) then
        -- UUID exists but not in the correct format
        local new_line
        if line:match("%[task:") then
          -- Format is wrong but bracket exists
          new_line = line:gsub("%[task:[^%]]*%]", info.expected_format)
        else
          -- No bracket format, add it
          new_line = M._add_uuid_to_line(line, info.uuid)
        end

        vim.api.nvim_buf_set_lines(bufnr, line_idx, line_idx + 1, false, { new_line })
        fixed_count = fixed_count + 1
      end
    end
  end

  -- Strategy 2: Scan all lines for UUIDs and fix if needed
  for i, line in ipairs(lines) do
    for _, info in ipairs(uuids) do
      -- Check if line has the UUID but in an incorrect format
      if not line:match(info.expected_format) and line:match(info.uuid) then
        -- This line has the UUID but not in the correct format
        local new_line
        if line:match("%[task:") then
          -- Format is wrong but bracket exists
          new_line = line:gsub("%[task:[^%]]*%]", info.expected_format)
        else
          -- No bracket format, add it
          new_line = M._add_uuid_to_line(line, info.uuid)
        end

        -- Skip if already fixed
        if line ~= new_line then
          vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { new_line })
          fixed_count = fixed_count + 1

          -- Update line in our local cache so we don't double-process
          lines[i] = new_line

          -- Update task location in cache
          core.update_task_location(info.uuid, vim.api.nvim_buf_get_name(bufnr), i)
        end
      end
    end
  end

  if fixed_count > 0 then
    utils.notify("Fixed " .. fixed_count .. " task references after formatting", vim.log.levels.INFO)
  end

  -- Clear the pre-format state
  pcall(vim.api.nvim_buf_del_var, bufnr, "taskforge_tags_pre_format")
end

-- Add UUID to a line in a formatter-friendly way
function M._add_uuid_to_line(line, uuid)
  local ft = vim.bo.filetype
  local lang = require("taskforge.lang").get_for_buffer()

  -- Use language module to add UUID properly
  if lang.add_uuid_to_comment then
    return lang.add_uuid_to_comment(line, uuid, ft)
  end

  -- Fallback implementation
  if line:match("%*/+%s*$") then
    -- Block comment, insert before closing */
    return line:gsub("%*/+%s*$", " [task:" .. uuid .. "] */")
  else
    -- Just append
    return line .. " [task:" .. uuid .. "]"
  end
end

-- Check if a formatter is active for a buffer
function M.has_active_formatter(bufnr)
  -- Check for formatter capability in LSP clients
  for _, client in ipairs(vim.lsp.get_active_clients({ bufnr = bufnr })) do
    if client.server_capabilities.documentFormattingProvider then
      return true
    end
  end

  -- Check for other known formatters
  local has_null_ls = pcall(require, "null-ls")
  local has_conform = pcall(require, "conform")
  local has_format = pcall(require, "format")

  return has_null_ls or has_conform or has_format
end

-- Public API for manually fixing UUIDs after formatting
function M.fix_after_formatting(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M._repair_uuids(bufnr)
end

return M

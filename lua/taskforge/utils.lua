-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
--[[
Taskforge Utility Module
=======================
Purpose:
  Provides a collection of utility functions for the Taskforge plugin, including
  text manipulation, dashboard management, and data processing.
--]]

local M = {} -- IMPORTANT: This must be at the top!

---Reads the entire contents of a file
---@param path string Path to the file
---@return string|nil content File contents or nil if file cannot be opened
---@return string|nil error Error message if file cannot be opened
function M.read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil, "Could not open the file."
  end
  local content = file:read("*a")
  file:close()
  return content
end

---Checks if the current buffer is a dashboard
---@return boolean true if current buffer is a dashboard
function M.is_dashboard_open()
  local bufname = vim.api.nvim_buf_get_name(0)
  local buftype = vim.bo.filetype
  return string.match(bufname, "dashboard") or buftype == "dashboard" or buftype == "snacks_dashboard"
end

---Refreshes the current dashboard if open
---Supports both Snacks and standard dashboard plugins
function M.refresh_dashboard()
  if M.is_dashboard_open() then
    local ok, Snacks = pcall(require, "Snacks")
    if ok and Snacks and Snacks.dashboard and type(Snacks.dashboard.update) == "function" then
      Snacks.dashboard.update()
    elseif M.get_dashboard_config and type(M.get_dashboard_config) == "function" then
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_delete(bufnr, { force = true })
      local dashboard = require("dashboard")
      dashboard.setup(M.get_dashboard_config())
      dashboard:instance()
    end
  end
end

---Clips text to specified width, adding ellipsis if needed
---@param text string Text to clip
---@param width number Maximum width allowed
---@return string Clipped text, potentially with ellipsis
function M.clip_text(text, width)
  local r_len = M.utf8len(text)
  if r_len > width then
    text = text:sub(1, (width - r_len) - 4) .. "..."
  end
  return text
end

---Merges two arrays into a new array
---@param a table First array
---@param b table Second array
---@return table result Combined array with elements from both inputs
function M.merge_arrays(a, b)
  local result = {}
  table.move(a, 1, #a, 1, result)
  table.move(b, 1, #b, #a + 1, result)
  return result
end

---Escapes special characters in a pattern
---@param text string Text to escape
---@return string Escaped pattern
local function escape_pattern(text)
  return text:gsub("([^%w])", "%%%1")
end

---Processes project name according to configuration rules
---@param project_name string Original project name
---@param config table|nil Configuration with optional abbreviations and section handling
---@return string Modified project name
function M.replace_project_name(project_name, config)
  if config and config.project_abbreviations then
    for pattern, replacement in pairs(config.project_abbreviations) do
      project_name = project_name:gsub(pattern, replacement)
    end
  end

  if config and config.shorten_sections then
    local sep = config.separator or "."
    local escaped_sep = escape_pattern(sep)
    local pattern = "[^" .. escaped_sep .. "]+"
    local parts = {}
    for part in project_name:gmatch(pattern) do
      table.insert(parts, part)
    end
    for i = 1, #parts - 1 do
      parts[i] = parts[i]:sub(1, 1)
    end
    project_name = table.concat(parts, sep)
  end
  return project_name
end

---Counts UTF-8 characters in a string
---@param str string Input string
---@return number Length in UTF-8 characters
function M.utf8len(str)
  local len = 0
  for _ in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
    len = len + 1
  end
  return len
end

---Extracts a portion of a table
---@param tbl table Source table
---@param start_index number Starting index (inclusive)
---@param end_index number Ending index (inclusive)
---@return table Sliced portion of the table
function M.slice(tbl, start_index, end_index)
  local result = {}
  for i = start_index, end_index do
    table.insert(result, tbl[i])
  end
  return result
end

---Removes leading and trailing whitespace
---@param s string String to trim
---@return string Trimmed string
local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

---Checks if a trimmed line exists in a table of lines
---@param lines_table table Table of lines to search
---@param target_line string Line to find
---@return boolean true if line found
function M.in_table(lines_table, target_line)
  target_line = trim(target_line)
  for _, line in ipairs(lines_table) do
    if trim(line) == target_line then
      return true
    end
  end
  return false
end

---Parses ISO 8601 datetime string to timestamp
---@param datetime_str string DateTime string in format "YYYYMMDDTHHMMSSZ"
---@return number|nil timestamp Unix timestamp or nil if invalid
---@return string|nil error Error message if parsing fails
function M.parse_datetime(datetime_str)
  local year, month, day, hour, min, sec = datetime_str:match("(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z")
  if not year then
    return nil, "Invalid date-time format"
  end

  local datetime_table = {
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  }

  return os.time(datetime_table)
end

---Aligns text to the right within specified width
---@param text string Text to align
---@param max_length number Maximum width
---@return string Right-aligned text
function M.align_right(text, max_length)
  local text_length = M.utf8len(text)
  if text_length < max_length then
    return string.rep(" ", max_length - text_length) .. text
  else
    return text
  end
end

---Aligns text to the left within specified width
---@param text string Text to align
---@param max_length number Maximum width
---@return string Left-aligned text
function M.align_left(text, max_length)
  local text_length = M.utf8len(text)
  if text_length < max_length then
    return text .. string.rep(" ", max_length - text_length)
  else
    return text
  end
end

---Centers text within specified width
---@param text string Text to center
---@param width number Total width
---@return string Centered text
function M.align_center(text, width)
  local text_length = M.utf8len(text)
  if text_length >= width then
    return text
  end
  local padding = (width - text_length) / 2
  local left_padding = math.floor(padding)
  local right_padding = math.ceil(padding)
  return string.rep(" ", left_padding) .. text .. string.rep(" ", right_padding)
end

---Formats ISO datetime string using os.date
---@param datetime_str string DateTime string in ISO format
---@param format_str string|nil Format string (default: "%Y-%m-%d %H:%M:%S")
---@return string Formatted date string
function M.get_os_date(datetime_str, format_str)
  format_str = format_str or "%Y-%m-%d %H:%M:%S"
  local timestamp, err = M.parse_datetime(datetime_str)
  if timestamp then
    return os.date(format_str, timestamp)
  end
  return "Invalid date: " .. (err or "unknown error")
end

---Sorts table of tasks by specified column
---@param tasks table Table of tasks
---@param column string Column name to sort by
---@param order string|nil Sort order ("asc" or "desc", default: "desc")
function M.sort_by_column(tasks, column, order)
  order = order or "desc"
  table.sort(tasks, function(a, b)
    if order == "desc" then
      return a[column] > b[column]
    else
      return a[column] < b[column]
    end
  end)
end

-- Debug functions
-- Write to the debug log file
function M.debug_log(module, message, data)
  -- Use pcall to avoid errors when config isn't loaded yet
  local cfg = {}
  local ok, config_module = pcall(require, "taskforge.config")
  if ok then
    cfg = config_module.get()
  end

  if not (cfg.debug and cfg.debug.enable) then
    return
  end

  local msg = string.format("[%s] %s", module, message)

  -- Add data inspection if provided
  if data ~= nil then
    if type(data) == "string" then
      msg = msg .. " " .. data
    else
      msg = msg .. " " .. vim.inspect(data)
    end
  end

  -- Write to log file if configured
  if cfg.debug and cfg.debug.log_file then
    local file = io.open(cfg.debug.log_file, "a")
    if file then
      file:write(os.date("%Y-%m-%d %H:%M:%S ") .. msg .. "\n")
      file:close()
    end
  end

  -- Also notify if debug is set to high verbosity
  if cfg.debug and cfg.debug.verbose then
    vim.schedule(function()
      vim.notify(msg, vim.log.levels.DEBUG)
    end)
  end
end

-- Run diagnostics
function M.run_diagnostics()
  M.debug_log("DEBUG", "Starting diagnostics")

  -- Test Neovim version
  local nvim_version = vim.version()
  M.debug_log(
    "DEBUG",
    "Neovim version:",
    string.format("%d.%d.%d", nvim_version.major, nvim_version.minor, nvim_version.patch)
  )

  -- Test taskwarrior
  M.test_taskwarrior()

  -- Test tasks data
  M.test_tasks_data()

  -- Check Snacks
  M.check_snacks()

  -- Dump config
  local ok, config_module = pcall(require, "taskforge.config")
  if ok then
    M.debug_log("DEBUG", "Configuration:", config_module.get())
  end

  M.debug_log("DEBUG", "Diagnostics complete")
end

-- Test taskwarrior connection
function M.test_taskwarrior()
  local Job = require("plenary.job")
  local output = {}
  local error_output = {}

  M.debug_log("DEBUG", "Testing taskwarrior connection")

  Job:new({
    command = "task",
    args = { "--version" },
    on_stdout = function(_, line)
      table.insert(output, line)
    end,
    on_stderr = function(_, line)
      table.insert(error_output, line)
    end,
    on_exit = function(_, code)
      if code == 0 then
        M.debug_log("DEBUG", "Taskwarrior version:", table.concat(output, "\n"))
      else
        M.debug_log("DEBUG", "Taskwarrior error:", table.concat(error_output, "\n"))
      end
    end,
  }):start()
end

-- Test tasks data
function M.test_tasks_data()
  local Job = require("plenary.job")
  local output = {}
  local error_output = {}

  M.debug_log("DEBUG", "Testing task export")

  Job:new({
    command = "task",
    args = { "export" },
    on_stdout = function(_, line)
      table.insert(output, line)
    end,
    on_stderr = function(_, line)
      table.insert(error_output, line)
    end,
    on_exit = function(_, code)
      if code == 0 then
        local data = table.concat(output, "")
        if data and data ~= "" then
          local ok, parsed = pcall(vim.json.decode, data)
          if ok then
            M.debug_log("DEBUG", "Task export successful, found " .. #parsed .. " tasks")
            -- Log a sample task
            if #parsed > 0 then
              M.debug_log("DEBUG", "Sample task:", parsed[1])
            end
          else
            M.debug_log("DEBUG", "Failed to parse task data:", parsed)
          end
        else
          M.debug_log("DEBUG", "Task export returned empty data")
        end
      else
        M.debug_log("DEBUG", "Task export error:", table.concat(error_output, "\n"))
      end
    end,
  }):start()
end

-- Check if Snacks dashboard is available
function M.check_snacks()
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks then
    M.debug_log("DEBUG", "Snacks is available")

    if Snacks.dashboard then
      M.debug_log("DEBUG", "Snacks dashboard is available")
    else
      M.debug_log("DEBUG", "Snacks dashboard is not available")
    end
  else
    M.debug_log("DEBUG", "Snacks is not available")
  end
end

-- Safely notify with fallback
function M.notify(msg, level)
  level = level or vim.log.levels.INFO
  vim.schedule(function()
    vim.notify(msg, level)
  end)
end

-- Centralized confirm dialog function that properly handles y/n keys
function M.confirm(prompt, opts)
  opts = opts or {}
  local choices = opts.choices or "&Yes\n&No"
  local default = opts.default or 2 -- Default to "No" for safety

  -- Schedule to ensure running in the main thread for proper key handling
  return vim.schedule_wrap(function(callback)
    local choice = vim.fn.confirm(prompt, choices, default)
    if callback then
      callback(choice)
    end
    return choice
  end)
end

-- Wrapper for simple yes/no confirmations
function M.confirm_yesno(prompt, callback, default_no)
  local default = default_no == false and 1 or 2 -- Default to "No" unless explicitly set to false
  return M.confirm(prompt, {
    choices = "&Yes\n&No",
    default = default,
  })(callback)
end

return M

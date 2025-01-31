-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
--[[
Taskforge Utility Module
=======================
Purpose:
  Provides a collection of utility functions for the Taskforge plugin, including
  command execution, text manipulation, dashboard management, and data processing.

Module Structure:
  - Uses Neovim API (vim.api) for buffer operations
  - Uses vim.fn for Vim function access
  - Requires Taskforge.utils.result for Result type handling
  - Exports functions through module table M

Major Components:
  1. Command Execution
     - Async/sync command execution with streaming support
     - Output processing with separator handling
     - Error handling with Result type

  2. Text Processing
     - UTF-8 aware text manipulation
     - Text alignment (left, right, center)
     - Text clipping with ellipsis
     - Pattern escaping and matching

  3. Dashboard Management
     - Dashboard buffer detection
     - Dashboard refresh handling
     - Multiple dashboard type support

  4. Data Structure Operations
     - Array merging and slicing
     - Table searching and sorting
     - Project name processing

  5. Date/Time Handling
     - ISO datetime parsing
     - OS date formatting
     - Timestamp conversion

Dependencies:
  - Neovim 0.10+ for vim.system()
  - Taskforge.utils.result for Result type
  - Optional dashboard plugins (Snacks, dashboard)
--]]

local api = vim.api
local fn = vim.fn

local Result = require("taskforge.utils.result")

local M = {}

---@class Taskforge.utils.Streams
---@field stdout function Iterator for stdout lines
---@field stderr function Iterator for stderr lines

---@class Taskforge.utils.ExecResult
---@field code number Exit code of the process
---@field signal number|nil Signal that terminated the process, if any
---@field streams Taskforge.utils.Streams|nil Stream iterators when in streaming mode
---@field stdout string[]|nil Complete stdout output when not streaming
---@field stderr string[]|nil Complete stderr output when not streaming
---@field timeout boolean True if process was terminated due to timeout

---@class Taskforge.utils.ExecError
---@field code number Exit code of the process
---@field stderr string Error output from the process
---@field message string Human readable error message

---@class Taskforge.utils.ExecOptions
---@field async boolean|nil Execute asynchronously (default: false)
---@field timeout number|nil Timeout in milliseconds (only for async)
---@field env table|nil Environment variables to set
---@field clear_env boolean|nil Clear environment before setting env variables
---@field cwd string|nil Working directory for command execution
---@field stream boolean|nil Stream output instead of collecting (only for async, default: false)
---@field separators string[]|nil Separators for splitting stdout (default: {"\n"})
---@field remove_sep boolean|nil Remove separators from output (default: true)

---Split text using multiple separators while preserving empty elements
---Note: Separators are treated as literal strings, not regex patterns
---Order of separators may affect the output when they overlap
---@param text string Text to split
---@param separators string[] Array of separator strings
---@param remove_sep boolean Whether to remove separators from output
---@return string|string[] Single string if empty/single result, array otherwise
local function split_text(text, separators, remove_sep)
  -- Handle the trivial case
  if text == "" then
    return ""
  end

  -- First split by each separator in sequence
  local parts = { text }
  for _, sep in ipairs(separators) do
    local new_parts = {}
    for _, part in ipairs(parts) do
      -- Split and process each part
      local start = 1
      local pattern = vim.pesc(sep)
      while start <= #part do
        local sep_start, sep_end = part:find(pattern, start, true)
        if not sep_start then
          -- Add remaining part (including empty strings)
          table.insert(new_parts, part:sub(start))
          break
        end

        -- Add part with or without separator
        local piece = remove_sep and part:sub(start, sep_start - 1) or part:sub(start, sep_end)
        table.insert(new_parts, piece)

        -- Move past this separator
        start = sep_end + 1
      end
    end
    parts = new_parts
  end

  -- Return appropriate type based on result count
  if #parts == 0 then
    return ""
  elseif #parts == 1 then
    return parts[1]
  end

  return parts
end

---Creates a line iterator that handles unicode characters correctly
---@param buffer table Table containing output chunks
---@param separators string[] Separators for splitting
---@param remove_sep boolean Whether to remove separators
---@return function Iterator function
local function create_line_iterator(buffer, separators, remove_sep)
  -- Process buffer content with unicode awareness
  local lines = split_text(table.concat(buffer), separators, remove_sep)

  -- Handle single string result
  if type(lines) == "string" then
    lines = { lines }
  end

  local idx = 0
  return function()
    idx = idx + 1
    return idx <= #lines and lines[idx] or nil
  end
end

---Creates an error result for command execution
---@param code number Error code
---@param stderr string Error output
---@param message string Error message
---@return Taskforge.utils.Result<Taskforge.utils.ExecResult, Taskforge.utils.ExecError>
local function make_error(code, stderr, message)
  return Result.err({
    code = code,
    stderr = stderr,
    message = message,
  })
end

---Creates a standardized result object from process output
---@param output table Output from vim.system or similar
---@param stdout_buffer table|nil Buffer containing stdout chunks
---@param stderr_buffer table|nil Buffer containing stderr chunks
---@param stream boolean|nil Whether to use streaming
---@param separators string[] Separators for splitting stdout
---@param remove_sep boolean Whether to remove separators
---@return Taskforge.utils.ExecResult
local function create_result(output, stdout_buffer, stderr_buffer, stream, separators, remove_sep)
  local result = {
    code = output.code or -1,
    signal = output.signal,
    timeout = false,
  }

  if stream then
    result.streams = {
      stdout = create_line_iterator(stdout_buffer or {}, separators, remove_sep),
      stderr = create_line_iterator(stderr_buffer or {}, { "\n" }, true),
    }
    result.stdout = nil
    result.stderr = nil
  else
    result.streams = nil
    -- Process outputs with unicode awareness
    local stdout_text = table.concat(stdout_buffer or {})
    local stderr_text = table.concat(stderr_buffer or {})

    result.stdout = split_text(stdout_text, separators, remove_sep)
    result.stderr = split_text(stderr_text, { "\n" }, true)
  end

  return result
end

---Execute a command with given options
---@param cmd string Command to execute
---@param args string[]|nil Arguments for the command
---@param opts Taskforge.utils.ExecOptions|nil Options for execution
---@param callback function|nil Callback for async execution (required if async=true)
---@return Taskforge.utils.Result<Taskforge.utils.ExecResult|nil, Taskforge.utils.ExecError>
function M.exec(cmd, args, opts, callback)
  -- Default options
  local opts_default = {
    async = false,
    separators = { "\n" },
    remove_sep = true,
  }

  opts = vim.tbl_deep_extend("force", opts_default, opts or {})
  args = args or {}

  -- Validate options
  if opts.async and not callback then
    return make_error(-1, "", "Callback is required for async execution")
  end

  if opts.stream and not opts.async then
    return make_error(-1, "", "Streaming is only available in async mode")
  end

  -- Prepare command arguments
  local command = { cmd }
  vim.list_extend(command, args)

  -- Prepare system options
  local system_opts = {
    cwd = opts.cwd,
    env = opts.env,
    clear_env = opts.clear_env,
  }

  if opts.timeout then
    system_opts.timeout = opts.timeout
  end

  if opts.async then
    -- Setup output handling for async mode
    local stdout_buffer = {}
    local stderr_buffer = {}

    -- Always capture output in async mode
    system_opts.stdout = function(_, data)
      if data then
        table.insert(stdout_buffer, data)
      end
    end

    system_opts.stderr = function(_, data)
      if data then
        table.insert(stderr_buffer, data)
      end
    end

    -- Start async process
    local handle = vim.system(command, system_opts, function(obj)
      -- Process the buffers according to separators
      local result = create_result({
        code = obj.code,
        signal = obj.signal,
      }, stdout_buffer, stderr_buffer, opts.stream, opts.separators, opts.remove_sep)

      -- Handle different completion states
      if obj.code ~= 0 then
        callback(
          make_error(
            obj.code,
            table.concat(split_text(table.concat(stderr_buffer), { "\n" }, true), "\n"),
            "Process failed with code " .. obj.code
          )
        )
      else
        callback(Result.ok(result))
      end
    end)

    if not handle then
      return make_error(-1, "", "Failed to start process")
    end
    return Result.ok(nil) -- Successful async start
  else
    -- Synchronous execution
    local result = vim.system(command, system_opts):wait()

    -- Handle different completion states
    if result.code ~= 0 then
      -- Process stderr according to newline separator
      local stderr = split_text(result.stderr or "", { "\n" }, true)
      return make_error(
        result.code,
        type(stderr) == "table" and table.concat(stderr, "\n") or stderr,
        "Process failed with code " .. result.code
      )
    end

    -- Process outputs directly
    local stdout = result.stdout or ""
    local stderr = result.stderr or ""

    return Result.ok(create_result({
      code = result.code,
      signal = result.signal,
    }, { stdout }, { stderr }, false, opts.separators, opts.remove_sep))
  end
end

---Reads the entire contents of a file
---@param path string Path to the file
---@return string|nil content File contents or nil if file cannot be opened
function M.read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

---Checks if the current buffer is a dashboard
---@return boolean true if current buffer is a dashboard
function M.is_dashboard_open()
  local bufname = api.nvim_buf_get_name(0)
  local buftype = vim.bo.filetype
  return string.match(bufname, "dashboard") or buftype == "dashboard" or buftype == "snacks_dashboard"
end

---Refreshes the current dashboard if open
---Supports both Snacks and standard dashboard plugins
function M.refresh_dashboard()
  if M.is_dashboard_open() then
    local Snacks = require("Snacks")
    if Snacks and Snacks.dashboard and type(Snacks.dashboard.update) == "function" then
      Snacks.dashboard.update()
    elseif M.get_dashboard_config and type(M.get_dashboard_config) == "function" then
      local bufnr = api.nvim_get_current_buf()
      api.nvim_buf_delete(bufnr, { force = true })
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
    local sep = config.sec_sep
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
    if line == target_line then
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
  return os.date(format_str, M.parse_datetime(datetime_str))
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

return M

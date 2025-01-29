-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
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
---@field stdout string|nil Complete stdout output when not streaming
---@field stderr string|nil Complete stderr output when not streaming
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

---Creates a line iterator from a buffer table
---@param buffer table Table containing output lines
---@return function Iterator function
local function create_line_iterator(buffer)
  local idx = 0
  return function()
    idx = idx + 1
    return idx <= #buffer and buffer[idx] or nil
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
---@param stdout_buffer table|nil Buffer containing stdout lines for streaming
---@param stderr_buffer table|nil Buffer containing stderr lines for streaming
---@param timed_out boolean|nil Whether process timed out
---@param stream boolean|nil Whether to use streaming
---@return Taskforge.utils.ExecResult
local function create_result(output, stdout_buffer, stderr_buffer, timed_out, stream)
  local result = {
    code = output.code or -1,
    signal = output.signal,
    timeout = timed_out or false,
  }

  if stream then
    result.streams = {
      stdout = create_line_iterator(stdout_buffer or {}),
      stderr = create_line_iterator(stderr_buffer or {}),
    }
    result.stdout = nil
    result.stderr = nil
  else
    result.streams = nil
    result.stdout = output.stdout or ""
    result.stderr = output.stderr or ""
  end

  return result
end

---Execute a command with given options
---@param cmd string Command to execute
---@param args string[]|nil Arguments for the command
---@param opts Taskforge.utils.ExecOptions|nil Options for execution
---@param callback function|nil Callback for async execution (required if async=true)
---@return Taskforge.utils.Result<Taskforge.utils.ExecResult|nil, Taskforge.utils.ExecError> Returns Result object containing either ExecResult or error
function M.exec(cmd, args, opts, callback)
  opts = opts or {}
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
      -- Process the result
      -- For non-streaming, join the buffers
      local stdout = opts.stream and stdout_buffer or table.concat(stdout_buffer)
      local stderr = opts.stream and stderr_buffer or table.concat(stderr_buffer)
      local result = create_result({
        code = obj.code,
        signal = obj.signal,
        stdout = stdout,
        stderr = stderr,
      }, stdout_buffer, stderr_buffer, nil, opts.stream)

      -- Handle different completion states
      if result.timeout then
        callback(
          make_error(
            124,
            vim.trim(table.concat(stderr_buffer, "\n")),
            "Process timed out after " .. opts.timeout .. "ms"
          )
        )
      elseif result.code ~= 0 then
        callback(
          make_error(
            result.code,
            opts.stream and vim.trim(table.concat(stderr_buffer, "\n")) or result.stderr,
            "Process failed with code " .. result.code
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
      return make_error(result.code, result.stderr, "Process failed with code " .. result.code)
    end

    return Result.ok(create_result(result, nil, nil, false, false))
  end
end

--
-- Function to read file contents
function M.read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

-- Function to check if the Dashboard buffer is open
function M.is_dashboard_open()
  -- Get the current buffer name
  local bufname = api.nvim_buf_get_name(0)

  -- Get the current buffer filetype
  local buftype = vim.bo.filetype

  -- Check if the buffer name contains 'dashboard' or filetype is 'dashboard'
  if string.match(bufname, "dashboard") or buftype == "dashboard" or buftype == "snacks_dashboard" then
    return true
  end
  return false
end

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

---Clips text to given width and if the text is longer than given width it will add "..."
---@param text string text to clip
---@param width number max width that text can have
---@return string text Clipped text
function M.clip_text(text, width)
  local r_len = M.utf8len(text)
  if r_len > width then
    text = text:sub(1, (width - r_len) - 4) .. "..."
  end
  return text
end

function M.merge_arrays(a, b)
  local result = {}
  table.move(a, 1, #a, 1, result)
  table.move(b, 1, #b, #a + 1, result)
  return result
end

--- Escapes special characters in a pattern
local function escape_pattern(text)
  return text:gsub("([^%w])", "%%%1")
end

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

function M.utf8len(str)
  local len = 0
  for _ in string.gmatch(str, "[%z\1-\127\194-\244][\128-\191]*") do
    len = len + 1
  end
  return len
end

--- Slices a table from start index to end index
---@param tbl table The input table
---@param start_index number The starting index
---@param end_index number The ending index
---@return table result The sliced portion of the table
function M.slice(tbl, start_index, end_index)
  local result = {}
  for i = start_index, end_index do
    table.insert(result, tbl[i])
  end
  return result
end
local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end
function M.in_table(lines_table, target_line)
  target_line = trim(target_line)
  for _, line in ipairs(lines_table) do
    if line == target_line then
      return true
    end
  end
  return false
end
function M.parse_datetime(datetime_str)
  -- Extract components using pattern matching
  local year, month, day, hour, min, sec = datetime_str:match("(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z")
  if not year then
    return nil, "Invalid date-time format"
  end

  -- Create a table with the extracted components
  local datetime_table = {
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  }

  -- Convert the table to a timestamp
  local timestamp = os.time(datetime_table)
  return timestamp
end

function M.align_right(text, max_length)
  local text_length = M.utf8len(text)
  if text_length < max_length then
    return string.rep(" ", max_length - text_length) .. text
  else
    return text
  end
end

function M.align_left(text, max_length)
  local text_length = M.utf8len(text)
  if text_length < max_length then
    return text .. string.rep(" ", max_length - text_length)
  else
    return text
  end
end

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

function M.get_os_date(datetime_str, format_str)
  -- log("utils.M.get_os_date", "datetime_str: " .. datetime_str)
  if not format_str then
    format_str = "%Y-%m-%d %H:%M:%S"
  end
  -- log("utils.M.get_os_date", "format_str: " .. format_str)
  return os.date(format_str, M.parse_datetime(datetime_str))
end

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

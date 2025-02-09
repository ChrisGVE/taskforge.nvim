-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
--[[
Taskforge Execution Module
=======================
Purpose:
  Facilitate the execution of command asynchronously or synchronously.

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

Dependencies:
  - Neovim 0.10+ for vim.system()
  - Taskforge.utils.result for Result type
--]]

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
---@field text boolean|nil Handle stdin and stderr as text

---Split text using multiple separators while preserving empty elements
---Note: Separators are treated as literal strings, not regex patterns
---Order of separators may affect the output when they overlap
---@param text string Text to split
---@param separators string[] Array of separator strings
---@param remove_sep boolean Whether to remove separators from output
---@return string|string[] Single string if empty/single result, array otherwise
local function split_text(text, separators, remove_sep)
  -- Handle the trivial cases
  if text == "" then
    return ""
  end

  if separators == nil or #separators == 0 then
    return text
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
  if opts.async and callback == nil then
    return make_error(-1, "", "Callback is required for async execution")
  end

  if opts.stream and not opts.async then
    return make_error(-1, "", "Streaming is only available in async mode")
  end

  -- Prepare command arguments
  local command = { cmd, unpack(args) }

  -- Prepare system options
  local system_opts = {}
  local system_opts_handle = { "cwd", "env", "clear_env", "timeout", "text" }
  for _, handle in ipairs(system_opts_handle) do
    if opts[handle] ~= nil then
      system_opts[handle] = opts[handle]
    end
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
        -- Process the buffers according to separators
        local result = create_result({
          code = obj.code,
          signal = obj.signal,
        }, stdout_buffer, stderr_buffer, opts.stream, opts.separators, opts.remove_sep)
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

return M

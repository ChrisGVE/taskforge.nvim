-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
--[[
Result Type Module
=================
Purpose:
  Provides a Result type for error handling, inspired by Rust's Result type.
  Wraps either a success value or an error value with type safety.

Requirements and Assumptions:
---------------------------
Module Structure:
  - Standalone module
  - Uses Lua metatables for computed properties
  - Returns single table with factory functions

Type System:
  - Uses LuaLS annotations for type checking
  - Supports generic type parameters for value and error types
  - Maintains type safety across transformations

Properties:
  - ok: boolean flag for success state
  - err: computed boolean, always opposite of ok
  - value: holds success value (nil if error)
  - error: holds error value (nil if success)

Performance Considerations:
  - Metatable lookup adds minimal overhead
  - Single metatable shared across all Result instances
  - Memory overhead is one table per Result instance plus one shared metatable
--]]

---@class Taskforge.utils.Result<T, E>
---@field ok boolean Whether the operation was successful
---@field err boolean Whether the operation was unsuccessful (computed from ok)
---@field value T|nil The result if ok is true
---@field error E|nil The error information if ok is false

local M = {}

-- Create shared metatable with err property
local result_mt = {
  __index = function(t)
    -- Only compute err property
    if rawget(t, "ok") ~= nil then
      return not t.ok
    end
  end,
}

---Creates a success Result
---@generic T
---@param value T
---@return Taskforge.utils.Result<T, any>
function M.ok(value)
  return setmetatable({
    ok = true,
    value = value,
    error = nil,
  }, result_mt)
end

---Creates an error Result
---@generic E
---@param error E
---@return Taskforge.utils.Result<any, E>
function M.err(error)
  return setmetatable({
    ok = false,
    value = nil,
    error = error,
  }, result_mt)
end

return M

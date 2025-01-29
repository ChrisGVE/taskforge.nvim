-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
---@class Taskforge.utils.Result<T, E>
---@field ok boolean Whether the operation was successful
---@field value T|nil The result if ok is true
---@field error E|nil The error information if ok is false

local M = {}

---Creates a success Result
---@generic T
---@param value T
---@return Taskforge.utils.Result<T, any>
function M.ok(value)
  return {
    ok = true,
    value = value,
    error = nil,
  }
end

---Creates an error Result
---@generic E
---@param error E
---@return Taskforge.utils.Result<any, E>
function M.err(error)
  return {
    ok = false,
    value = nil,
    error = error,
  }
end

return M

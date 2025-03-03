-- lua/taskforge/lang/init.lua
-- Language detection and loading module

local M = {}

local debug = require("taskforge.debug")

-- Cache of loaded language modules
local language_cache = {}

-- Get the appropriate language module for a buffer
function M.get_for_buffer(bufnr)
  bufnr = bufnr or 0
  local filetype = vim.bo[bufnr].filetype

  -- Check cache first
  if language_cache[filetype] then
    return language_cache[filetype]
  end

  -- Try to load specific language module
  local ok, lang_module = pcall(require, "taskforge.lang." .. filetype)
  if ok then
    language_cache[filetype] = lang_module
    return lang_module
  end

  -- Fall back to common language module
  local common = require("taskforge.lang.common")
  language_cache[filetype] = common
  return common
end

-- Check if a buffer is supported
function M.is_supported(bufnr)
  bufnr = bufnr or 0
  local ft = vim.bo[bufnr].filetype
  local bufname = vim.api.nvim_buf_get_name(bufnr)

  -- Debug log the buffer
  debug.log("LANG", "Checking buffer support", {
    buffer = bufnr,
    name = bufname,
    filetype = ft,
  })

  -- Skip special buffer types
  if vim.bo[bufnr].buftype ~= "" then
    debug.log("LANG", "Skipping special buffer type", vim.bo[bufnr].buftype)
    return false
  end

  -- Always consider these filetypes unsupported
  local unsupported = {
    "",
    "help",
    "NvimTree",
    "fugitive",
    "gitcommit",
    "startify",
  }

  for _, v in ipairs(unsupported) do
    if ft == v then
      debug.log("LANG", "Skipping unsupported filetype", ft)
      return false
    end
  end

  -- Special case for dashboard and snacks_dashboard filetypes
  -- Skip actual dashboard buffers but NOT files named dashboard.lua
  if (ft == "dashboard" or ft == "snacks_dashboard") and not bufname:match("dashboard%.lua$") then
    debug.log("LANG", "Skipping dashboard buffer (not dashboard.lua)", ft)
    return false
  end

  debug.log("LANG", "Buffer is supported")
  return true
end

return M

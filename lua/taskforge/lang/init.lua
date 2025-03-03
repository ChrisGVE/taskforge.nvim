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
    "dashboard",
    "snacks_dashboard",
    "quickfix",
    "nofile",
    "prompt",
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

  -- Check if this filetype is in the enabled_ft config
  local config = require("taskforge.config")
  local enabled_ft = config.get().tags.enabled_ft or { "*" }

  if not vim.tbl_contains(enabled_ft, "*") and not vim.tbl_contains(enabled_ft, ft) then
    debug.log("LANG", "Filetype not enabled in config", ft)
    return false
  end

  debug.log("LANG", "Buffer is supported")
  return true
end

-- Create an interface validator for language modules
function M.validate_language_module(module)
  -- Required functions for a valid language module
  local required_functions = {
    "is_comment_string",
    "extract_tag_info",
    "detect_comment_context",
    "add_uuid_to_comment",
  }

  for _, func_name in ipairs(required_functions) do
    if type(module[func_name]) ~= "function" then
      return false, "Missing required function: " .. func_name
    end
  end

  -- Required properties
  if not module.name or not module.comment_patterns then
    return false, "Missing required properties"
  end

  return true, "Valid language module"
end

return M

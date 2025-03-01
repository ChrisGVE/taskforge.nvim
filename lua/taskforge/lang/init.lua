-- lua/taskforge/lang/init.lua
-- Language detection and loading module

local M = {}

-- Cache of loaded language modules
local language_cache = {}

-- Get the appropriate language module for a buffer
-- @param bufnr number Buffer number
-- @return table Language module with comment handling functions
function M.get_for_buffer(bufnr)
  bufnr = bufnr or 0
  local filetype = vim.bo[bufnr].filetype

  -- Check cache first
  if language_cache[filetype] then
    return language_cache[filetype]
  end

  -- Try LSP-based detection first
  local lsp_lang = M._get_from_lsp(bufnr)
  if lsp_lang then
    language_cache[filetype] = lsp_lang
    return lsp_lang
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

-- Attempt to get language information from LSP
-- @param bufnr number Buffer number
-- @return table|nil Language module if available from LSP
function M._get_from_lsp(bufnr)
  -- Only proceed if LSP is available
  if not vim.lsp or not vim.lsp.get_active_clients then
    return nil
  end

  local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
  if not clients or #clients == 0 then
    return nil
  end

  -- Check if any client has document symbol support (could help identify comments)
  local has_symbol_support = false
  local client_with_symbols = nil

  for _, client in ipairs(clients) do
    if client.server_capabilities and client.server_capabilities.documentSymbolProvider then
      has_symbol_support = true
      client_with_symbols = client
      break
    end
  end

  if not has_symbol_support then
    return nil
  end

  -- Create a language module that uses LSP for enhanced detection
  local lsp_lang = {
    name = "lsp_enhanced",
    client = client_with_symbols,

    -- Get comment nodes using LSP document symbols
    get_comment_nodes = function(buf)
      local result = {}

      -- This is where we would query LSP for document symbols
      -- and filter for comments, but this isn't directly supported
      -- by most language servers.

      -- For now, we return an empty result as this is just a template
      return result
    end,

    -- Check if LSP can provide comment information
    has_comment_support = function()
      return false -- Most LSPs don't directly support comment queries
    end,
  }

  -- Merge with filetype-specific module if available
  local ft = vim.bo[bufnr].filetype
  local ok, ft_module = pcall(require, "taskforge.lang." .. ft)

  if ok then
    -- Combine LSP capability with filetype-specific patterns
    for k, v in pairs(ft_module) do
      if not lsp_lang[k] then
        lsp_lang[k] = v
      end
    end
  else
    -- Merge with common module for basic patterns
    local common = require("taskforge.lang.common")
    for k, v in pairs(common) do
      if not lsp_lang[k] then
        lsp_lang[k] = v
      end
    end
  end

  return lsp_lang
end

-- Helper function to check if a buffer is supported
function M.is_supported(bufnr)
  bufnr = bufnr or 0
  local ft = vim.bo[bufnr].filetype

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
  }

  for _, v in ipairs(unsupported) do
    if ft == v then
      return false
    end
  end

  -- Skip special buffer types
  if vim.bo[bufnr].buftype ~= "" then
    return false
  end

  return true
end

return M

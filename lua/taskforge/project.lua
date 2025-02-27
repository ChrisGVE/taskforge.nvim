-- lua/taskforge/project.lua
-- Project detection and management
-- Uses LSP, VCS, and pattern matching to determine current project

local M = {}
local uv = vim.uv or vim.loop
local config = require("taskforge.config")

function M.setup()
  M.cache = {
    current_project = nil,
    root_patterns = {},
    synonyms = {},
  }
  M._build_root_patterns()
  M._load_synonyms()
end

function M.current()
  return M.cache.current_project or M.detect()
end

function M.detect()
  local cfg = config.get().project
  local detection_order = { "lsp", "vcs", "pattern" }
  local root

  -- Check enabled detection methods
  for _, method in ipairs(detection_order) do
    if cfg.detection_methods[method] then
      root = M["_detect_" .. method .. "_root"]()
      if root and not M._is_excluded(root) then
        break
      end
    end
  end

  return root and M._format_project_name(root) or cfg.default_project
end

function M._detect_lsp_root()
  local clients = vim.lsp.get_clients()
  for _, client in ipairs(clients) do
    if client.config.root_dir then
      return client.config.root_dir
    end
  end
end

function M._detect_vcs_root()
  local markers = { ".git", ".hg", ".svn" }
  local path = uv.fs_realpath(vim.fn.expand("%:p:h"))

  while path ~= "/" do
    for _, marker in ipairs(markers) do
      if uv.fs_stat(path .. "/" .. marker) then
        return path
      end
    end
    path = uv.fs_realpath(path .. "/..")
  end
end

function M._detect_pattern_root()
  local cfg = config.get().project
  local path = uv.fs_realpath(vim.fn.expand("%:p:h"))

  while path ~= "/" do
    for _, pattern in ipairs(M.cache.root_patterns) do
      if uv.fs_stat(path .. "/" .. pattern) then
        return path
      end
    end
    path = uv.fs_realpath(path .. "/..")
  end
end

function M._is_excluded(path)
  local excludes = config.get().project.root_patterns.exclude_dirs
  return vim.tbl_contains(excludes, vim.fn.fnamemodify(path, ":t"))
end

function M._format_project_name(path)
  local cfg = config.get().project
  local name = path:gsub("[/\\]", cfg.separator)

  -- Apply prefix/postfix
  name = table.concat({
    cfg.prefix,
    name,
    cfg.postfix == "PATH" and path or "",
  }, cfg.separator)

  -- Apply synonyms
  return M.cache.synonyms[name] or name
end

function M._build_root_patterns()
  local cfg = config.get().project.root_patterns
  M.cache.root_patterns = vim.Iter:flatten({
    cfg.extensions,
    cfg.signature,
    cfg.json,
  })
end

function M._load_synonyms()
  local syn = config.get().project.project_synonyms
  for proper_name, variants in pairs(syn) do
    if type(variants) == "table" then
      for _, variant in ipairs(variants) do
        M.cache.synonyms[variant] = proper_name
      end
    else
      M.cache.synonyms[variants] = proper_name
    end
  end
end

return M

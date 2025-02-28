-- lua/taskforge/project.lua
-- Project detection and management
-- Uses LSP, VCS, and pattern matching to determine current project

local M = {}
local uv = vim.uv or vim.loop
local config = require("taskforge.config")
local utils = require("taskforge.utils")

function M.setup()
  M.cache = {
    current_project = nil,
    root_patterns = {},
    synonyms = {},
    file_to_project = {}, -- Cache of file to project mapping
  }
  M._build_root_patterns()
  M._load_synonyms()

  -- Set up file rename watcher if available
  if vim.lsp and vim.lsp.handlers then
    M._setup_lsp_rename_handler()
  end
end

-- Get current project, with caching
function M.current()
  -- Get the current file
  local current_file = vim.fn.expand("%:p")

  -- If file hasn't changed, use cached project
  if M.cache.current_file == current_file and M.cache.current_project then
    return M.cache.current_project
  end

  -- Check if this file is in our cache
  if M.cache.file_to_project[current_file] then
    M.cache.current_file = current_file
    M.cache.current_project = M.cache.file_to_project[current_file]
    return M.cache.current_project
  end

  -- Detect project for this file
  local project = M.detect()

  -- Cache the result
  M.cache.current_file = current_file
  M.cache.current_project = project
  M.cache.file_to_project[current_file] = project

  return project
end

-- Detect project based on configured methods
function M.detect()
  local cfg = config.get().project
  local detection_order = { "lsp", "vcs", "pattern", "json" }
  local root

  -- Check enabled detection methods
  for _, method in ipairs(detection_order) do
    if cfg.detection_methods[method] then
      root = M["_detect_" .. method .. "_root"]()
      if root and not M._is_excluded(root) then
        utils.debug_log("PROJECT", "Detected project root using " .. method, root)
        break
      end
    end
  end

  if not root then
    utils.debug_log("PROJECT", "Using default project", cfg.default_project)
    return cfg.default_project
  end

  -- Extract project name based on configuration
  local project_name = M._format_project_name(root)
  utils.debug_log("PROJECT", "Final project name", project_name)
  return project_name
end

-- Detect project root using LSP
function M._detect_lsp_root()
  if not vim.lsp then
    return nil
  end

  local clients = vim.lsp.get_clients()
  for _, client in ipairs(clients) do
    if client.config and client.config.root_dir then
      return client.config.root_dir
    end
  end
  return nil
end

-- Detect project root using version control system markers
function M._detect_vcs_root()
  local markers = { ".git", ".hg", ".svn", ".bzr", "_darcs" }
  local path = uv.fs_realpath(vim.fn.expand("%:p:h"))

  if not path then
    return nil
  end

  while path and path ~= "/" do
    for _, marker in ipairs(markers) do
      local marker_path = path .. "/" .. marker
      local stat = uv.fs_stat(marker_path)
      if stat then
        utils.debug_log("PROJECT", "Found VCS marker", marker_path)
        return path
      end
    end
    -- Go up one directory
    local parent = uv.fs_realpath(path .. "/..")
    if parent == path then
      -- We've reached the root
      break
    end
    path = parent
  end

  return nil
end

-- Detect project root using configured patterns
function M._detect_pattern_root()
  local path = uv.fs_realpath(vim.fn.expand("%:p:h"))

  if not path then
    return nil
  end

  while path and path ~= "/" do
    for _, pattern in ipairs(M.cache.root_patterns) do
      local pattern_path = path .. "/" .. pattern
      local stat = uv.fs_stat(pattern_path)
      if stat then
        utils.debug_log("PROJECT", "Found pattern", pattern_path)
        -- If this is a file, extract project name from filename
        if stat.type == "file" and not vim.endswith(pattern, "/") then
          -- Handle .csproj, .xcodeproj as special cases
          if vim.endswith(pattern, ".csproj") or vim.endswith(pattern, ".xcodeproj") then
            local proj_name = vim.fn.fnamemodify(pattern, ":r")
            utils.debug_log("PROJECT", "Extracted project name from file", proj_name)
            -- Return with format: path|projectname
            return path .. "|" .. proj_name
          end
        end
        return path
      end
    end
    -- Go up one directory
    local parent = uv.fs_realpath(path .. "/..")
    if parent == path then
      -- We've reached the root
      break
    end
    path = parent
  end

  return nil
end

-- Detect project using JSON files
function M._detect_json_root()
  local cfg = config.get().project
  local path = uv.fs_realpath(vim.fn.expand("%:p:h"))

  if not path or not cfg.root_patterns.json then
    return nil
  end

  while path and path ~= "/" do
    for _, json_file in ipairs(cfg.root_patterns.json) do
      local json_path = path .. "/" .. json_file
      local stat = uv.fs_stat(json_path)

      if stat and stat.type == "file" then
        utils.debug_log("PROJECT", "Found JSON file", json_path)
        -- Try to read and parse the JSON file
        local content = utils.read_file(json_path)
        if content then
          local ok, json_data = pcall(vim.fn.json_decode, content)
          if ok and json_data then
            -- Extract project name from JSON based on configured tags
            local project_name = M._extract_name_from_json(json_data, cfg.json_tags)
            if project_name then
              utils.debug_log("PROJECT", "Extracted project name from JSON", project_name)
              return path .. "|" .. project_name
            end
          end
        end
        -- If we couldn't extract a name, just return the path
        return path
      end
    end
    -- Go up one directory
    local parent = uv.fs_realpath(path .. "/..")
    if parent == path then
      -- We've reached the root
      break
    end
    path = parent
  end

  return nil
end

-- Extract project name from JSON object using a list of possible keys
function M._extract_name_from_json(json_data, keys)
  -- Try each key in the list
  for _, key in ipairs(keys) do
    if json_data[key] and type(json_data[key]) == "string" then
      return json_data[key]
    end
  end

  -- Try nested objects
  for _, key in ipairs(keys) do
    for obj_key, obj_value in pairs(json_data) do
      if type(obj_value) == "table" and obj_value[key] and type(obj_value[key]) == "string" then
        return obj_value[key]
      end
    end
  end

  return nil
end

-- Check if directory should be excluded
function M._is_excluded(path)
  local excludes = config.get().project.root_patterns.exclude_dirs
  local dir_name = vim.fn.fnamemodify(path, ":t")
  return vim.tbl_contains(excludes, dir_name)
end

-- Format detected project path into a project name
function M._format_project_name(path)
  local cfg = config.get().project
  local project_name = ""
  local extracted_name = nil

  -- Check if path has an extracted name (path|name format)
  if type(path) == "string" and string.find(path, "|") then
    local parts = vim.split(path, "|")
    path = parts[1]
    extracted_name = parts[2]
  end

  -- First, get the base directory name
  local base_name = extracted_name or vim.fn.fnamemodify(path, ":t")

  -- Apply prefix if configured
  if cfg.prefix and cfg.prefix ~= "" then
    project_name = cfg.prefix
    if not string.match(project_name, cfg.separator .. "$") then
      project_name = project_name .. cfg.separator
    end
  end

  -- Add the project name (from extraction or base dir)
  project_name = project_name .. base_name

  -- Handle postfix based on configuration
  if cfg.postfix and cfg.postfix ~= "" then
    -- Get current file relative to project root
    local current_file = vim.fn.expand("%:p")
    local rel_path = string.sub(current_file, #path + 2) -- +2 to skip the trailing slash

    if cfg.postfix == "PATH" or string.find(cfg.postfix, "PATH") then
      -- Add full path
      local dir_path = vim.fn.fnamemodify(rel_path, ":h")
      if dir_path and dir_path ~= "." then
        project_name = project_name .. cfg.separator .. dir_path:gsub("/", cfg.separator)
      end
    end

    if cfg.postfix == "FILENAME" or string.find(cfg.postfix, "FILENAME") then
      -- Add filename without extension
      local filename = vim.fn.fnamemodify(rel_path, ":t:r")
      if filename and filename ~= "" then
        project_name = project_name .. cfg.separator .. filename
      end
    end

    if cfg.postfix == "EXT" or string.find(cfg.postfix, "EXT") then
      -- Add file extension
      local ext = vim.fn.fnamemodify(rel_path, ":e")
      if ext and ext ~= "" then
        project_name = project_name .. cfg.separator .. ext
      end
    end
  end

  -- Apply synonyms if configured
  if M.cache.synonyms[project_name] then
    project_name = M.cache.synonyms[project_name]
  end

  -- Remove extension if configured
  if cfg.remove_extension then
    project_name = project_name:gsub("%.[^%.]+$", "")
  end

  return project_name
end

-- Build list of patterns to check for project root
function M._build_root_patterns()
  local cfg = config.get().project.root_patterns

  -- Use vim.iter (lowercase) to flatten arrays
  M.cache.root_patterns = vim
    .iter({
      cfg.extensions or {},
      cfg.signature or {},
      cfg.json or {},
    })
    :flatten()
    :totable()
end

-- Load configured project name synonyms
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

-- Set up LSP handler for file renames
function M._setup_lsp_rename_handler()
  -- We need to handle workspace/didRenameFiles notification
  vim.lsp.handlers["workspace/didRenameFiles"] = function(err, result, ctx, config)
    -- Call the default handler first
    local original_handler = vim.lsp.handlers["workspace/didRenameFiles"]
    if original_handler then
      original_handler(err, result, ctx, config)
    end

    -- Now handle the file renames for our tasks
    if result and result.files then
      for _, file_change in ipairs(result.files) do
        local old_uri = file_change.oldUri
        local new_uri = file_change.newUri

        -- Convert URIs to paths
        local old_path = vim.uri_to_fname(old_uri)
        local new_path = vim.uri_to_fname(new_uri)

        utils.debug_log("PROJECT", "File renamed", { old = old_path, new = new_path })

        -- Update our file to project cache
        if M.cache.file_to_project[old_path] then
          local project = M.cache.file_to_project[old_path]
          M.cache.file_to_project[new_path] = project
          M.cache.file_to_project[old_path] = nil
        end

        -- Emit event for tasks to update
        local tasks = require("taskforge.tasks")
        if tasks.handle_file_rename then
          tasks.handle_file_rename(old_path, new_path)
        end
      end
    end
  end
end

return M

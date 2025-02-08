-- Credit for the inspiration of this module goos to Ahmedkhalf
-- https://github.com/ahmedkhalf/project.nvim

local M = {}

local utils = require("taskforge.utils.utils")
local glob = require("taskforge.utils.globtopattern")
local config = require("taskforge.utils.config")
local uv = vim.loop
local api = vim.api
local fn = vim.fn

M.attached_lsp = false

-- Get the lsp client for the current buffer
---@return string|nil error
function M.find_lsp_root()
  local buf_ft = api.nvim_get_option_value("filetype", {})
  local clients = vim.lsp.get_clients()

  -- log(buf_ft, clients)

  if next(clients) == nil then
    return nil
  end

  for _, client in pairs(clients) do
    local filetypes = client.config.filetypes
    if filetypes and vim.tbl_contains(filetypes, buf_ft) then
      return client.config.root_dir
    end
  end

  return nil
end

function M.set_pwd(dir)
  if dir ~= nil then
    if fn.getcwd() ~= dir then
      api.nvim_set_current_dir(dir)
    end
    return true
  end

  return false
end

function M.is_excluded(dir)
  if config.project.root_patterns.exclude_dirs == nil then
    return false
  end
  for _, dir_pattern in ipairs(config.project.root_patterns.exclude_dirs) do
    if dir:match(dir_pattern) ~= nil then
      return true
    end
  end

  return false
end

function M.exists(path_name)
  return vim.fn.empty(vim.fn.glob(path_name)) == 0
end

---@return string|nil,string|nil, string|nil
function M.find_pattern_root()
  local search_dir = fn.expand("%:p:h", true)
  if fn.has("win32") > 0 then
    search_dir = search_dir:gsub("\\", "/")
  end

  -- log("search dir:", search_dir)

  local last_dir_cache = ""
  local curr_dir_cache = {}

  local function get_parent(path_name)
    path_name = path_name:match("^(.*)/")
    if path_name == "" then
      path_name = "/"
    end
    return path_name
  end

  local function get_files(file_dir)
    last_dir_cache = file_dir
    curr_dir_cache = {}

    local dir = uv.fs_scandir(file_dir)
    if dir == nil then
      return
    end

    while true do
      local file = uv.fs_scandir_next(dir)
      if file == nil then
        return
      end
      table.insert(curr_dir_cache, file)
    end
  end

  ---@return boolean
  local function is(dir, identifier)
    dir = dir:match(".*/(.*)")
    return dir == identifier
  end

  ---@return boolean
  local function sub(dir, identifier)
    local path_name = get_parent(dir)
    while true do
      if is(path_name, identifier) then
        return true
      end
      local current = path_name
      path_name = get_parent(path_name)
      if current == path_name then
        return false
      end
    end
  end

  ---@return boolean
  local function child(dir, identifier)
    local path_name = get_parent(dir)
    return is(path_name, identifier)
  end

  ---@return boolean
  local function has(dir, identifier)
    if last_dir_cache ~= dir then
      get_files(dir)
    end
    local pattern = glob.globtopattern(identifier)
    for _, file in ipairs(curr_dir_cache) do
      if file:match(pattern) ~= nil then
        return true
      end
    end
    return false
  end

  local function match(dir, pattern)
    local first_char = pattern:sub(1, 1)
    if first_char == "=" then
      return is(dir, pattern:sub(2))
    elseif first_char == "^" then
      return sub(dir, pattern:sub(2))
    elseif first_char == ">" then
      return child(dir, pattern:sub(2))
    else
      return has(dir, pattern)
    end
  end

  while true do
    -- log("search dir: ", search_dir)
    for pattern_type, pattern_list in pairs(config.project.root_patterns) do
      -- log("type: ", pattern_type)
      for _, pattern in ipairs(pattern_list) do
        -- log("pattern: ", pattern)
        local exclude = false
        if pattern:sub(1, 1) == "!" then
          exclude = true
          pattern = pattern:sub(2)
        end
        if match(search_dir, pattern) then
          if exclude then
            break
          else
            return search_dir, pattern_type, pattern
          end
        end
      end
    end

    local parent = get_parent(search_dir)
    if parent == search_dir or parent == nil then
      return nil
    end

    search_dir = parent
  end
end

---Determine the current project. Will use several heuristic to determine the project name
---if none succeeds it will return nil
---@return string|nil, string|nil, string|nil
function M.get_project_root()
  for _, detection_method in ipairs(config.project.detection_methods) do
    if detection_method == "lsp" then
      local root, lsp_name = M.find_lsp_root()
      if root ~= nil and not M.is_excluded(root) then
        return root, lsp_name, "lsp"
      end
    elseif detection_method == "pattern" then
      local root, pattern_type, method = M.find_pattern_root()
      if root ~= nil and not M.is_excluded(root) then
        return root, pattern_type, method
      end
    end
  end
  return nil
end

function M.get_project_name()
  local root, pattern_type, method = M.get_project_root()
  -- log(root, pattern_type, method)

  if root == nil or root == "" then
    return nil
  end

  local project_name = ""
  if root ~= nil then
    -- default value
    project_name = root:match("/*.*/(.*)$")
    -- log("default name:", project_name)
  end

  if method == "json" then
    if config.project.json_tags ~= nil and #config.project.json_tags ~= 0 then
      local content = utils.read_file(root .. "/" .. method)
      if content ~= nil then
        local json = fn.json_decode(content)
        if json ~= nil then
          for _, tag in ipairs(config.project.json_tags) do
            if json[tag] ~= nil then
              project_name = json[tag]
              -- log("json:", project_name)
            end
          end
        end
      end
    end
  end

  if method == "extension" then
    local name = root:match(".*/(.*)\\" .. method)
    if name ~= nil then
      project_name = name
    end
  end

  -- If method is "signature" we already have the project name as it is the default value
  -- if method == "signature" then
  --   project_name = root:match("/*.*/(.*)$")
  -- end

  -- if the extension must be removed we do it unless the project name starts with a dot
  if project_name ~= "" and project_name:sub(1, 1) ~= "." and config.project.remove_extension then
    project_name = project_name:match("([^.]*)[\\.]*.*$")
  end

  -- we look for synonmyms and if found we return the main name
  -- log("project synonyms: ", config.project.project_synonyms, #config.project.project_synonyms)
  if config.project.project_synonyms ~= nil then
    for project, synonym in pairs(config.project.project_synonyms) do
      -- log("Synonym:", project, synonym)
      if synonym ~= nil then
        if type(synonym) ~= nil and type(synonym) == "string" and project_name == synonym then
          return project
        end
        if type(synonym) ~= nil and type(synonym) == "table" then
          for _, term in pairs(synonym) do
            if project_name == term then
              return project
            end
          end
        end
      end
    end
  end

  return project_name
end

---@diagnostic disable-next-line: unused-local
local on_attach_lsp = function(client, bufnr)
  M.on_buf_enter()
end

function M.attach_to_lsp()
  if M.attached_lsp then
    return
  end

  local _start_client = vim.lsp.start_client
  vim.lsp.start_client = function(lsp_config)
    if lsp_config.on_attach == nil then
      lsp_config.on_attach = on_attach_lsp
    else
      local _on_attach = lsp_config.on_attach
      lsp_config.on_attach = function(client, bufnr)
        on_attach_lsp(client, bufnr)
        _on_attach(client, bufnr)
      end
    end
    return _start_client(lsp_config)
  end

  M.attached_lsp = true
end

function M.is_file()
  local buf_type = api.nvim_get_option_value("buftype", {})

  local whitelisted_buf_type = { "", "acwrite" }
  local is_in_whitelist = false
  for _, wtype in ipairs(whitelisted_buf_type) do
    if buf_type == wtype then
      is_in_whitelist = true
      break
    end
  end
  if not is_in_whitelist then
    return false
  end

  return true
end

function M.on_buf_enter()
  if vim.v.vim_did_enter == 0 then
    return
  end

  if not M.is_file() then
    return
  end

  local current_dir = fn.expand("%:p:h", true)
  if not M.exists(current_dir) or M.is_excluded(current_dir) then
    return
  end

  local root, _, _ = M.get_project_root()
  M.set_pwd(root)
end

function M.setup()
  local autocmds = {}
  autocmds[#autocmds + 1] = 'autocmd VimEnter,BufEnter * ++nested lua require("taskforge.project").on_buf_enter()'

  if vim.tbl_contains(config.project.detection_methods, "lsp") then
    M.attach_to_lsp()
  end

  vim.cmd([[
    command! ProjectRoot lua require("taskforge.project").on_buf_enter()
  ]])

  vim.cmd([[augroup project_nvim
            au!
  ]])
  for _, value in ipairs(autocmds) do
    vim.cmd(value)
  end
  vim.cmd("augroup END")
end

return M

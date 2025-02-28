-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--

-- Core Taskforge module
local M = {
  _config = nil,
  _initialized = false,
  _available_deps = {},
}

local function check_dependencies()
  -- Try to prefetch dependencies to avoid loading issues later
  local function try_require(module_name)
    local ok = pcall(require, module_name)
    return ok
  end

  -- Check if taskwarrior is installed
  if vim.fn.executable("task") ~= 1 then
    vim.notify("Taskforge: Taskwarrior command not found. Plugin functionality will be limited.", vim.log.levels.WARN)
    M._available_deps.taskwarrior = false
  else
    M._available_deps.taskwarrior = true
  end

  -- Check plenary - this is absolutely required
  local has_plenary = try_require("plenary")
  if not has_plenary then
    vim.notify("Taskforge: Required dependency 'plenary.nvim' not found. Plugin cannot function.", vim.log.levels.ERROR)
    return false
  end

  -- Check NUI components - we need at least some of these
  local has_nui_layout = try_require("nui.layout")
  local has_nui_tree = try_require("nui.tree")
  local has_nui_popup = try_require("nui.popup")

  if not (has_nui_layout or has_nui_tree or has_nui_popup) then
    vim.notify("Taskforge: nui.nvim components not found. Interface features disabled.", vim.log.levels.WARN)
    M._available_deps["nui.nvim"] = false
  else
    M._available_deps["nui.nvim"] = true
  end

  -- Check optional dependencies
  local opt_deps = {
    ["snacks"] = "folke/snacks.nvim",
    ["telescope"] = "nvim-telescope/telescope.nvim",
    ["fzf-lua"] = "ibhagwan/fzf-lua",
  }

  -- Check optional Lua dependencies
  for name, repo in pairs(opt_deps) do
    local ok = try_require(name)
    M._available_deps[name] = ok

    -- Only warn about missing dependency if it's the configured picker
    local picker_type = config and config.get and config.get().interface and config.get().interface.integrations
    if not ok and picker_type and picker_type[name] then
      vim.notify(
        "Taskforge: Configured picker '" .. repo .. "' not found. Falling back to built-in picker.",
        vim.log.levels.WARN
      )
    end
  end

  -- We can continue as long as we have plenary
  return true
end

function M.setup(user_opts)
  -- Don't initialize twice
  if M._initialized then
    return
  end

  -- Check dependencies
  if not check_dependencies() then
    vim.notify("Taskforge: Critical dependencies missing. Plugin disabled.", vim.log.levels.ERROR)
    return
  end

  -- Initialize configuration first
  M._config = require("taskforge.config")
  M._config.set(user_opts or {})

  -- Get config for debug setup
  local cfg = M._config.get()

  -- Setup debug module if enabled
  if cfg.debug and cfg.debug.enable then
    -- Check if snacks.debug is available
    local has_debug = pcall(require, "snacks.debug")
    if has_debug then
      local debug = require("snacks.debug")
      debug.setup(cfg.debug)
    end
  end

  -- Initialize core modules and system modules in the correct order to prevent circular dependencies
  require("taskforge.project").setup()
  require("taskforge.tasks").setup()

  -- Initialize UI modules
  if M._available_deps.taskwarrior then
    -- Configure taskwarrior
    require("taskforge.tasks").configure()

    -- Initialize tracker module
    require("taskforge.tracker").setup()

    -- Set up commands
    require("taskforge.commands").register()
  end

  -- Set initialization flag
  M._initialized = true

  -- Log initialization status
  if cfg.debug and cfg.debug.enable then
    utils.notify("Taskforge initialized successfully", vim.log.levels.INFO)
  end
end

-- Function to access dashboard from other plugins
function M.get_dashboard_section()
  if not M._initialized then
    -- Just do minimal initialization
    M._config = require("taskforge.config")
    local user_opts = {}
    M._config.set(user_opts)
  end

  -- Try the standalone dashboard first (for testing)
  local ok, standalone = pcall(require, "taskforge.standalone_dashboard")
  if ok and standalone.create_standalone_section then
    -- Don't try to use utils or other modules that might cause circular dependencies
    vim.notify("Using standalone dashboard section")
    return standalone.create_standalone_section()
  end

  -- Fall back to regular dashboard
  local ok_dashboard, dashboard = pcall(require, "taskforge.dashboard")
  if ok_dashboard then
    vim.notify("Using regular dashboard section")
    return dashboard.create_section()
  end

  vim.notify("No dashboard section available")
  return {}
end

-- Function to get project info
function M.get_current_project()
  if not M._initialized then
    M.setup({})
  end

  local ok, project = pcall(require, "taskforge.project")
  if ok then
    return project.current()
  end

  return nil
end

-- Function to open task interface
function M.open_task_interface()
  if not M._initialized then
    M.setup({})
  end

  if not M._available_deps.taskwarrior then
    vim.notify("Taskforge: Taskwarrior not available", vim.log.levels.ERROR)
    return
  end

  local ok, interface = pcall(require, "taskforge.interface")
  if ok then
    interface.open_task_interface()
  end
end

-- Function to open task picker
function M.open_task_picker()
  if not M._initialized then
    M.setup({})
  end

  if not M._available_deps.taskwarrior then
    vim.notify("Taskforge: Taskwarrior not available", vim.log.levels.ERROR)
    return
  end

  local ok, picker = pcall(require, "taskforge.picker")
  if ok then
    picker.open_task_picker()
  end
end

return M

-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--

-- Core Taskforge module
local M = {
  _config = nil,
  _initialized = false,
  _available_deps = {},
  _module_setup_order = {
    "taskforge.config",
    "taskforge.debug",
    "taskforge.project",
    "taskforge.tasks",
    "taskforge.tracker",
    -- UI modules are loaded separately via schedule
  },
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
    ["trouble"] = "folke/trouble.nvim",
  }

  -- Check optional Lua dependencies
  for name, repo in pairs(opt_deps) do
    local ok = try_require(name)
    M._available_deps[name] = ok
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

  -- Use our custom module loader to prevent circular dependencies
  local module_loader = require("taskforge.module")

  -- Initialize configuration first (outside module loader)
  local config_ok, config = pcall(require, "taskforge.config")
  if config_ok then
    M._config = config
    M._config.set(user_opts or {})
  else
    vim.notify("Failed to load config: " .. tostring(config), vim.log.levels.ERROR)
    return
  end

  -- Get config for debug setup
  local cfg = M._config.get()

  -- Setup debug module if enabled
  if cfg.debug and cfg.debug.enable then
    local debug_ok, debug_module = pcall(require, "taskforge.debug")
    if debug_ok then
      debug_module.setup(cfg.debug)
    end
  end

  -- Initialize core modules in order, using our protected module loader
  local module_results = module_loader.initialize(M._module_setup_order, cfg.debug and cfg.debug.enable)

  -- Configure taskwarrior if available
  if M._available_deps.taskwarrior then
    local tasks = module_loader.require("taskforge.tasks")
    pcall(tasks.configure)

    -- Set up commands
    local commands_ok, commands = pcall(require, "taskforge.commands")
    if commands_ok then
      pcall(commands.register)
    end

    -- Schedule UI initialization for later
    module_loader.schedule_ui_init()
  end

  -- Set initialization flag
  M._initialized = true

  -- Log initialization status
  if cfg.debug and cfg.debug.enable then
    vim.notify("Taskforge initialized successfully", vim.log.levels.INFO)
  end
end

-- Function to access dashboard section from other plugins
function M.get_dashboard_section()
  if not M._initialized then
    -- Do minimal initialization
    local config_ok, config = pcall(require, "taskforge.config")
    if config_ok then
      M._config = config
      M._config.set({})
    end
  end

  -- Try standalone dashboard first (for testing)
  local ok, standalone = pcall(require, "taskforge.standalone_dashboard")
  if ok and standalone.create_standalone_section then
    return standalone.create_standalone_section()
  end

  -- Fall back to regular dashboard
  local ok_dashboard, dashboard = pcall(require, "taskforge.dashboard")
  if ok_dashboard then
    return dashboard.create_section()
  end

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

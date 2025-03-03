-- lua/taskforge/module.lua
-- Module loader with circular dependency protection

local M = {}
local cache = {}
local loading = {}

-- Flag for lazy loading of UI components
M.ui_initialized = false

-- Load a module with circular dependency protection
-- @param module_name string Module name
-- @return table Module
function M.require(module_name)
  -- Return from cache if already loaded
  if cache[module_name] then
    return cache[module_name]
  end

  -- Detect circular dependency
  if loading[module_name] then
    -- Return empty table to break circular dependency
    local placeholder = {}
    cache[module_name] = placeholder
    return placeholder
  end

  -- Mark as loading
  loading[module_name] = true

  -- Load the module
  local success, module = pcall(require, module_name)

  -- Either store the module or a placeholder on error
  if success then
    cache[module_name] = module
  else
    vim.notify("Failed to load module: " .. module_name .. ": " .. module, vim.log.levels.ERROR)
    cache[module_name] = {}
  end

  -- Done loading
  loading[module_name] = nil

  return cache[module_name]
end

-- Initialize the specified modules in order
-- @param modules table List of module names
-- @param progress boolean Whether to show progress
function M.initialize(modules, progress)
  local results = {}
  local loaded = {}

  for i, module_name in ipairs(modules) do
    if progress then
      vim.notify("Initializing " .. module_name .. " (" .. i .. "/" .. #modules .. ")")
    end

    -- Only initialize each module once
    if not loaded[module_name] then
      local module = M.require(module_name)

      -- Call setup function if it exists
      if type(module.setup) == "function" then
        local success, result = pcall(module.setup)
        results[module_name] = success

        if not success then
          vim.notify("Error initializing " .. module_name .. ": " .. result, vim.log.levels.ERROR)
        end
      end

      loaded[module_name] = true
    end
  end

  return results
end

-- Schedule UI initialization to break dependency cycle
function M.schedule_ui_init()
  vim.schedule(function()
    if not M.ui_initialized then
      M.ui_initialized = true
      vim.notify("Initializing UI components...")

      -- Initialize UI-related modules
      M.initialize({
        "taskforge.ui",
        "taskforge.ui.theme",
        "taskforge.ui.dialog",
      })

      -- Initialize optional integrations
      local trouble_ok = pcall(require, "trouble")
      if trouble_ok then
        M.require("taskforge.integrations.trouble").setup()
      end
    end
  end)
end

return M

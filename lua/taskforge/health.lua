-- lua/taskforge/health.lua
local M = {}

function M.check()
  local health = vim.health

  health.start("Taskforge.nvim")

  -- Neovim version
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim 0.10+")
  else
    health.error("Neovim 0.10+ required")
  end

  -- Taskwarrior checks
  local tw_ok = M._check_taskwarrior()
  if tw_ok then
    M._check_tw_config()
  end

  -- Dependencies
  health.ok("Plenary: " .. tostring(package.loaded["plenary"] ~= nil))
  health.ok("NUI: " .. tostring(package.loaded["nui"] ~= nil))
  health.ok("Snacks: " .. tostring(package.loaded["snacks"] ~= nil))
end

function M._check_taskwarrior()
  if vim.fn.executable("task") == 1 then
    vim.health.ok("Taskwarrior installed")
    return true
  end
  vim.health.error("Taskwarrior not found")
  return false
end

function M._check_tw_config()
  local required = {
    rc_editor = "nvim",
    rc_confirmation = "off",
    rc_verbose = "no",
  }

  local missing = {}
  for setting, expected in pairs(required) do
    local actual = M._get_tw_config(setting)
    if actual ~= expected then
      table.insert(missing, setting .. "=" .. expected)
    end
  end

  if #missing > 0 then
    vim.health.warn("Run :Taskforge config to fix:\n" .. table.concat(missing, "\n"))
  else
    vim.health.ok("Taskwarrior configured")
  end
end

function M._get_tw_config(setting)
  local job = require("plenary.job"):new({
    command = "task",
    args = { "_get", setting },
  })
  return table.concat(job:sync(), "")
end

return M

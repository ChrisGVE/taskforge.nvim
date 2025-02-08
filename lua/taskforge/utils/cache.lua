-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--
local utils = require("taskforge.utils.utils")

-- Default cache structure
Cache = {
  has_taskwarrior = nil,
  has_taskwarrior_tui = nil,
  has_taskopen = nil,
  -- database
  data_file = nil,
  data_file_exists = nil,
  -- has dashboard plugins
  has_snacks_dashboard = nil,
  has_dashboard = nil,
  -- has picker plugins
  has_snacks_picker = nil,
  has_telescope = nil,
  has_fzf_lua = nil,
  -- Main switch
  valid = nil,
}

function Cache:setup()
  -- setup environment cache
  self.has_taskwarrior = vim.fn.executable("task") == 1
  self.has_taskwarrior_tui = vim.fn.executable("taskwarrior-tui") == 1
  self.has_taskopen = vim.fn.executable("taskopen") == 1

  -- get the data file location
  local opts = { separators = { "\n", " " } }
  local cmd = "task"
  local data_folder = utils.exec(cmd, { "_get", "rc.data.location" }, opts) --[[@as Taskforge.utils.Result]]
  if data_folder.ok then
    self.data_file = data_folder.value.stdout .. "/taskchampion.sqlite3"
    self.data_file_exists = vim.fn.filereadable(self.data_file) == 1
  else
    self.data_file_exists = false
  end

  -- Which dashboard do we have available
  self.has_snacks_dashboard = package.loaded["Snacks.dashboard"] ~= nil
  self.has_dashboard = package.loaded["dashboard-nvim"] ~= nil

  -- Which picker do we have available
  self.has_snacks_picker = package.loaded["Snacks.picker"] ~= nil
  self.has_telescope = package.loaded["telescope"] ~= nil
  self.has_fzf_lua = package.loaded["fzf-lua"] ~= nil

  -- Main switch
  self.valid = self.has_taskwarrior and self.data_file_exists and vim.fn.has("nvim-0.10") == 1
end

return Cache

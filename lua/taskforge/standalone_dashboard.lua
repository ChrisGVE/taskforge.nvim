-- A simplified standalone dashboard module just for testing
-- This doesn't depend on other modules

local M = {}

-- Create a simple dashboard section with hardcoded items
function M.create_standalone_section()
  vim.notify("Creating standalone dashboard section")

  -- Create a simple title
  local title = {
    icon = "",
    title = "Tasks (Standalone)",
    pane = 2,
  }

  -- Create simple text items
  local items = {
    { "Project: taskforge", hl = "dir", width = 45, align = "center" },
    { "\n", hl = "dir" },
    { "⚑ TODO: Implement dashboard display", hl = "special" },
    { "\n", hl = "dir" },
    { "⚑ FIX: Fix dashboard integration", hl = "special" },
    { "\n", hl = "dir" },
    { "--+--", hl = "dir", width = 45, align = "center" },
    { "\n", hl = "dir" },
    { "⚑ PERF: Optimize tag detection", hl = "normal" },
    { "\n", hl = "dir" },
  }

  -- Create the section
  local section = {
    pane = 2,
    padding = 1,
    indent = 3,
    text = items,
    height = 10,
  }

  vim.notify("Created standalone section with " .. #items .. " items")

  return { title, section }
end

return M

-- lua/taskforge/interface.lua
-- Interactive task management interface
-- Uses NUI.nvim for task tree visualization

local M = {}
local nui = require("nui")
local Layout = nui.Layout
local Tree = nui.Tree

function M.open_task_interface()
  local cfg = require("taskforge.config").get().interface
  local tasks = require("taskforge.tasks").list()

  local tree = Tree({
    win_options = {
      number = false,
      relativenumber = false,
      wrap = false,
    },
    nodes = M._build_tree_nodes(tasks),
    prepare_node = function(node)
      return {
        text = ("  "):rep(node.level) .. node.task.description,
        highlight = node.task.urgency > 8 and "TaskforgeUrgent" or "Normal",
      }
    end,
  })

  local layout = Layout({
    position = cfg.position or "right",
    size = cfg.size or { width = 0.8, height = 0.9 },
    buf_options = {
      modifiable = false,
      readonly = true,
    },
  }, {
    left = tree,
    right = M._create_detail_panel(),
  })

  layout:mount()
  layout:on(event.BufLeave, function()
    layout:unmount()
  end)
end

function M._create_detail_panel()
  local text = require("nui.text")
  return text({
    data = { "Select a task to view details" },
    win_options = {
      number = false,
      relativenumber = false,
      wrap = true,
    },
  })
end

function M._build_tree_nodes(tasks)
  local nodes = {}
  local task_map = {}

  -- Build dependency tree
  for _, task in ipairs(tasks) do
    task_map[task.id] = task
    task.children = {}
  end

  for _, task in ipairs(tasks) do
    if task.depends then
      for _, dep_id in ipairs(task.depends) do
        if task_map[dep_id] then
          table.insert(task_map[dep_id].children, task)
        end
      end
    end
  end

  -- Convert to NUI nodes
  local function add_children(parent_task, level)
    for _, child in ipairs(parent_task.children) do
      table.insert(nodes, {
        task = child,
        level = level,
        children = #child.children > 0,
      })
      if #child.children > 0 then
        add_children(child, level + 1)
      end
    end
  end

  -- Find root tasks
  for _, task in ipairs(tasks) do
    if not task.depends or #task.depends == 0 then
      table.insert(nodes, { task = task, level = 0 })
      add_children(task, 1)
    end
  end

  return nodes
end

M.open_tt = function()
  if vim.fn.executable("taskwarrior-tui") == 1 then
    local cmd = { "taskwarrior-tui" }
    local opts = {
      interactive = true,
      win = {
        style = "terminal",
        width = 0.9,
        height = 0.9,
        border = "rounded",
        title = "Taskwarrior-tui",
        title_pos = "center",
      },
    }
    Snacks.terminal(cmd, opts)
  end
end

return M

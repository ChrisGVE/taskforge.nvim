-- Unified picker interface supporting multiple backends
-- Runtime dependency checks with config fallbacks

local M = {}
local config = require("taskforge.config")

function M.open_task_picker()
  local picker_type = config.get_picker_type()
  local tasks = require("taskforge.tasks").list()

  if picker_type == "snacks" then
    return M._snacks_picker(tasks)
  elseif picker_type == "telescope" then
    return M._telescope_picker(tasks)
  elseif picker_type == "fzf" then
    return M._fzf_picker(tasks)
  else
    return M._native_picker(tasks)
  end
end

function M._snacks_picker(tasks)
  local snacks = require("snacks.picker")
  snacks(tasks, {
    format_item = M._format_task,
    handler = function(task)
      require("taskforge.interface").open(task)
    end,
  })
end

function M._telescope_picker(tasks)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")

  pickers
    .new({}, {
      finder = finders.new_table({
        results = tasks,
        entry_maker = function(task)
          return {
            value = task,
            display = M._format_task(task),
            ordinal = task.description,
          }
        end,
      }),
      sorter = require("telescope.config").values.generic_sorter({}),
      attach_mappings = function(_, map)
        map("i", "<cr>", function(prompt_bufnr)
          local entry = require("telescope.actions.state").get_selected_entry()
          require("telescope.actions").close(prompt_bufnr)
          require("taskforge.interface").open(entry.value)
        end)
        return true
      end,
    })
    :find()
end

function M._format_task(task)
  local cfg = require("taskforge.config").get()
  return string.format(
    "[%s] %s (%.2f)",
    task.project:sub(1, cfg.dashboard.project_abbr_len or 12),
    task.description,
    task.urgency
  )
end

function M._fzf_picker(tasks)
  local fzf = require("fzf-lua")
  fzf.fzf_exec(tasks, {
    to_item = function(task)
      return M._format_task(task)
    end,
    actions = {
      ["default"] = function(selected)
        require("taskforge.interface").open(selected[1])
      end,
    },
    previewer = function(task)
      return string.format("Project: %s\nUrgency: %.2f\nDescription: %s", task.project, task.urgency, task.description)
    end,
  })
end

function M._native_picker(tasks)
  vim.ui.select(tasks, {
    prompt = "Select Task:",
    format_item = function(task)
      return string.format("%s [%s] (%.2f)", task.description, task.project, task.urgency)
    end,
  }, function(selected)
    if selected then
      require("taskforge.interface").open(selected)
    end
  end)
end

return M

-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
local M = {}

-- local main_ui = require("taskforge.main-ui")
-- local tag_tracker = require("taskforge.tag-tracker") -- not implemented yet
local tasks = require("taskforge.tasks")
local api = vim.api

function M.get_markdown_todos(project, group_by, limit)
  local todos = tasks.get_todo(project, group_by, limit) or {}
  local todos_lines = {}
  for _, todo in ipairs(todos) do
    table.insert(todos_lines, string.rep(" ", todo.indent * 2) .. "- [ ] " .. todo.task.description)
  end
  return todos_lines
end

function M.render_markdown_todos(project, group_by, limit)
  local todos_lines = M.get_markdown_todos(project, group_by, limit)
  local row, col = unpack(api.nvim_win_get_cursor(0))
  api.nvim_buf_set_lines(0, row, row, true, todos_lines)
  api.nvim_win_set_cursor(0, { row + #todos_lines, col })
end

return M

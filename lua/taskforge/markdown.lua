-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
local M = {}

local tasks = require("taskforge.interface")
-- local tag_tracker = require("taskforge.tag_tracker") -- not implemented yet
local interface = require("taskforge.interface")
local dashboard = require("taskforge.dashboard")
local utils = require("taskforge.utils.utils")
local api = vim.api

local function setup_commands()
	api.nvim_create_user_command("Task2ToDo", function(opts)
		require("taskforge").render_markdown_todos(unpack(opts.fargs))
	end, { nargs = "*" })
end

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

function M.test()
	print(table.concat(M.get_markdown_todos("personal", "depends"), "\n"))
end

function M.setup()
	log()
	setup_commands()
end

return M

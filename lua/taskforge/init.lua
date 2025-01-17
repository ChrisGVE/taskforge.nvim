-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License

-- Core modules
local M = {}
local api = vim.api
local fn = vim.fn

-- Module imports
local tasks = require("taskforge.tasks")
-- local tag_tracker = require("taskforge.tag_tracker") -- not implemented yet
local interface = require("taskforge.tasks")
local dashboard = require("taskforge.dashboard")
local utils = require("taskforge.utils")

-- Constants
local PLUGIN_NAME = "taskforge.nvim"

-- Default configuration structure
M.config = {
	--- toggle the logging
	debug = true,
	-- Project naming configuration
	project = {
		-- project prefix, will be separated by a dot with the project name
		prefix = "",
		-- default project name for situations where the tagged files do not belong to a git project
		default_project = "project",
		-- indicate whether the postfix is made by the path of the tagged file, the filename of the tagged file or both
		postfix = "PATH|FILENAME",
		-- default separator, path components are replaced with this separator
		separator = ".",
	},

	-- Tag tracking configuration
	tags = {
		-- languages for which the plugin is active
		enabled_filetypes = {
			"c",
			"cpp",
			"go",
			"hjson",
			"java",
			"javascript",
			"lua",
			"markdown",
			"python",
			"rust",
			"typescript",
			"zig",
		},
		definitions = {
			-- format of the tags
			tag_format = ".*:",
			["TODO"] = {
				priority = "M",
				tags = { "coding", "enhancement" },
				due = "+1w",
				alt = {},
				create = "ask",
				close = "auto",
			},
			["WARN"] = {
				priority = "H",
				tags = { "coding", "warning" },
				due = "+3d",
				alt = { "WARNING", "XXX" },
				create = "auto",
				close = "auto",
			},
			["FIX"] = {
				priority = "H",
				tags = { "coding", "bug" },
				due = "+2d",
				alt = { "FIXME", "BUG", "FIXIT", "ISSUE" },
				create = "auto",
				close = "auto",
			},
			["PERF"] = {
				priority = "M",
				tags = { "coding", "performance" },
				due = "+1w",
				alt = { "OPTIM", "OPTIMIZE", "PERFORMANCE" },
				create = "auto",
				close = "ask",
			},
			["TEST"] = {
				priority = "L",
				tags = { "coding", "testing" },
				due = nil,
				alt = { "TESTING", "PASSED", "FAILED" },
				create = "auto",
				close = "manual",
			},
		},
	},

	-- Dashboard integration
	dashboard = {
		--- where information about the taskwarrior project can be found
		-- TODO: bring the project info at the global level of the config
		project_info = ".taskforge.json",
		--- function to reload dashboard config
		get_dashboard_config = nil,
		-- Options for Snacks.nvim dashboard
		snacks_options = {
			icon = "",
			title = "Tasks",
			height = nil,
			pane = nil,
			enable = false,
			padding = 1,
			indent = 3,
		},
		-- Options for Dashboard.nvim
		dashboard_options = {},
		format = {
			-- maximum number of tasks
			limit = 5,
			-- maximum number of non-project tasks
			non_project_limit = 5,
			-- Defines the section separator
			sec_sep = ".",
			-- Enable or disable section shortening
			shorten_sections = true,
			-- Maximum width
			max_width = 50,
			-- Columns to be shown
			columns = {
				"id",
				"project",
				"description",
				"due",
				"urgency",
			},
			-- Abbreviations to shorten project names
			project_abbreviations = {
				["work."] = "w.",
				["personal."] = "p.",
			},
		},
	},

	-- Task interface configuration
	interface = {
		keymaps = {
			open = "o", -- if tracked,
			close_task = "d",
			modify_task = "m",
			annotate_task = "A",
			add_task = "a",
			filter = "/",
			sort = "s",
			quit = "q",
		},
		view = {
			default = "list", -- or "tree" for dependency view
			position = "right",
			width = 40,
		},
		integrations = {
			telescope = true,
			fzf = true,
		},
	},

	-- Highlighting
	highlights = {
		urgent = {
			threshold = 8.0,
			group = nil, -- Will use @keyword if nil
		},
		normal = {
			group = nil, -- Will use Comment if nil
		},
	},
}

-- Command registration
function M.create_commands()
	-- api.nvim_create_user_command("TaskForge", function(opts)
	-- 	interface.toggle()
	-- end, {})
	--
	-- api.nvim_create_user_command("TaskForgeAdd", function(opts)
	-- 	interface.add_task(opts.args)
	-- end, { nargs = "*" })
end

-- Autocommand setup for tag tracking
-- function M.create_autocommands()
-- 	local group = api.nvim_create_augroup("TaskForge", { clear = true })
--
-- 	api.nvim_create_autocmd({ "BufEnter" }, {
-- 		group = group,
-- 		callback = function()
-- 			if utils.is_filetype_enabled() then
-- 				tag_tracker.scan_buffer()
-- 			end
-- 		end,
-- 	})
--
-- 	-- Debounced tag tracking
-- 	local timer = nil
-- 	api.nvim_create_autocmd({ "TextChanged", "TextChanged" }, {
-- 		group = group,
-- 		callback = function()
-- 			if utils.is_filetype_enabled() then
-- 				if timer then
-- 					timer:stop()
-- 				end
-- 				timer = vim.defer_fn(function()
-- 					tag_tracker.update_buffer()
-- 				end, 500) -- 500ms debounce
-- 			end
-- 		end,
-- 	})
-- end

local function setup_commands()
	vim.api.nvim_create_user_command("Task2ToDo", function(opts)
		require("taskforge").render_markdown_todos(unpack(opts.fargs))
	end, { nargs = "*" })
end

-- return the task section for dashboard.nvim
function M.get_dashboard_tasks()
	return dashboard.get_lines()
end

-- return the task section for Snacks.nvim dashboard
function M.get_snacks_dashboard_tasks()
	return dashboard.get_snacks_dashboard_tasks()
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
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	vim.api.nvim_buf_set_lines(0, row, row, true, todos_lines)
	vim.api.nvim_win_set_cursor(0, { row + #todos_lines, col })
end

function M.test()
	print(table.concat(M.get_markdown_todos("personal", "depends"), "\n"))
end

function M.get_dashboard_config()
	if M.config and M.config.dashboard.get_dashboard_config then
		return M.config.dashboard.get_dashboard_config()
	end
	return nil
end

-- Core setup function
---Setting utlis, tasks and dashboard
---@param user_config any
function M.setup(user_config)
	-- Merge configs
	M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

	-- Initialize modules with config
	tasks.setup(M.config)
	-- tag_tracker.setup(M.config) -- Not implemented yet
	-- interface.setup(M.config) -- Not implemented yet
	dashboard.setup(M.config)

	-- Set up commands
	M.create_commands()

	-- Set up autocommands for tag tracking
	-- M.create_autocommands()

	-- to be replaced with a standard logging library
	utils.debug = M.config.debug
	utils.log_message("init.M.setup", "------------------------------------")
	utils.log_message("init.M.setup", "Setting up Taskforge") -- Debug print
	utils.get_dashboard_config = M.config.get_dashboard_config

	setup_commands()
end

return M

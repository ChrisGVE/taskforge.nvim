local M = {}
local utils = require("taskforge.utils")
local tasks = require("taskforge.tasks")
local urgent_lines = {}
local not_urgent_lines = {}

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

			max_width = 50,
			columns = {
				"id",
				"project",
				"description",
				"due",
				"urgency",
			},
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

M.project = nil

---Check if the current buffer directory contains a project.json, if so,
---it return project name
---@return nil
local function get_project()
	local content = utils.read_file(M.config.dashboard.project_info)
	if content == nil then
		return nil
	end
	local json = vim.fn.json_decode(content)
	if json == nil or json.project == nil or json.project == "" then
		return nil
	end
	return json.project
end

---Clips text to given width and if the text is longer than given width it will add "..."
---@param text string text to clip
---@param width number max width that text can have
---@return string text Clipped text
local function clip_text(text, width)
	local r_len = utils.utf8len(text)
	if r_len > width then
		text = text:sub(1, (width - r_len) - 4) .. "..."
	end
	return text
end

local function parse_line(task, columnsWidth)
	local line = {}
	for _, column in ipairs(M.config.dashboard.format.columns) do
		local sl = " "
		if _ == 1 then
			sl = ""
		end
		local width = columnsWidth[column]
		local value = tostring(task[column] or "")
		if column == "project" and value ~= "" then
			value = "[" .. value .. "]"
		end
		value = clip_text(value, width)
		if column == "urgency" then
			table.insert(line, sl .. utils.align_right(value, width))
		else
			table.insert(line, sl .. utils.align_left(value, width))
		end
	end
	return table.concat(line, "")
end

local function sanitize_task(task)
	for k, v in pairs(task) do
		if v ~= nil then
			if k == "urgency" then
				task[k] = string.format("%.2f", v)
			elseif k == "due" then
				utils.log_message("dashboard.sanitize_task", "[" .. task["id"] .. "]" .. "due (v): " .. v)
				local current_year = os.date("%Y")
				local pattern = "^" .. current_year .. "%-(.*)"
				local date_string = tostring(utils.get_os_date(v, "%Y-%m-%d"))
				local new_date_string = date_string:match(pattern)
				task[k] = new_date_string or date_string
			elseif k == "project" then
				task[k] = utils.replace_project_name(v, M.config.dashboard.format)
			end
		else
			task[k] = ""
		end
	end
	return task
end

local function sanitize_tasks(task_list)
	for _, task in ipairs(task_list) do
		task = sanitize_task(task)
	end
end

local function get_columns_width(task_list, other_tasks, maxwidth)
	utils.log_message("dashboard.get_columns_width", "Getting columns width")
	local columnsWidth = {}
	-- TODO: Check if this is really necessary, also it should be independent from whether we target snacks.nvim or dashboard.nvim
	local max_width = maxwidth or M.config.dashboard.format.max_width
	local needed_for_padding = #M.config.dashboard.format.columns
	local total_width = 0
	sanitize_tasks(task_list)
	sanitize_tasks(other_tasks)
	for _, column in ipairs(M.config.dashboard.format.columns) do
		columnsWidth[column] = 0
		for _, task in ipairs(task_list) do
			if task[column] ~= nil then
				-- task = sanitize_task(task)
				columnsWidth[column] = math.max(columnsWidth[column], utils.utf8len(tostring(task[column])))
			end
		end
		for _, task in ipairs(other_tasks) do
			if task[column] ~= nil then
				-- task = sanitize_task(task)
				columnsWidth[column] = math.max(columnsWidth[column], utils.utf8len(tostring(task[column])))
			end
		end
		total_width = total_width + columnsWidth[column]
	end
	if columnsWidth["project"] ~= nil then
		columnsWidth["project"] = columnsWidth["project"] + 2
	end
	if columnsWidth["description"] ~= nil then
		local delta = (max_width - total_width) - needed_for_padding
		columnsWidth["description"] = columnsWidth["description"] + delta
	end
	return columnsWidth
end

function M.get_tasks()
	local main_tasts = tasks.tasks_get_urgent(M.config.dashboard.format.limit, M.project)
	local other_tasks = {}
	if
		M.project ~= nil
		and M.config.dashboard.format.non_project_limit ~= nil
		and M.config.dashboard.format.non_project_limit > 0
	then
		other_tasks = tasks.tasks_get_urgent(M.config.dashboard.format.non_project_limit, M.project, true)
	end
	return main_tasts, other_tasks
end

function M.get_lines(max_width)
	utils.log_message("dashboard.M.get_lines", "Getting lines")
	local lines = {}
	local task_list, other_tasks = M.get_tasks()
	local columnsWidth = get_columns_width(task_list, other_tasks, max_width)

	for _, task in ipairs(task_list) do
		local line = parse_line(task, columnsWidth)
		utils.log_message("dashboard.M.get_lines", "task.urgency: " .. tonumber(task.urgency))
		if
			task.urgency ~= nil
			and M.config.highlights.urgent.threshold ~= nil
			and tonumber(task.urgency) >= M.config.highlights.urgent.threshold
		then
			utils.log_message("dashboard.M.get_lines", "Adding urgent line")
			table.insert(urgent_lines, line)
		else
			utils.log_message("dashboard.M.get_lines", "Adding not urgent line")
			table.insert(not_urgent_lines, line)
		end
		table.insert(lines, line)
	end

	if #other_tasks > 0 and M.project and #task_list > 0 then
		table.insert(lines, "--+--")
	end

	for _, task in ipairs(other_tasks) do
		local line = parse_line(task, columnsWidth)
		utils.log_message("dashboard.M.get_lines", "task.urgency: " .. tonumber(task.urgency))
		if
			task.urgency ~= nil
			and M.config.highlights.urgent.threshold ~= nil
			and tonumber(task.urgency) >= M.config.highlights.urgent.threshold
		then
			utils.log_message("dashboard.M.get_lines", "Adding urgent line")
			table.insert(urgent_lines, line)
		else
			utils.log_message("dashboard.M.get_lines", "Adding not urgent line")
			table.insert(not_urgent_lines, line)
		end
		table.insert(lines, line)
	end
	return lines
end

function M.get_lines_for_snacks()
	local max_width = M.config.dashboard.format.max_width -- - M.config.dashboard.snacks_options.indent
	local hl_normal = "dir"
	local hl_overdue = "special"
	utils.log_message("dashboard.M.get_lines", "Getting lines")
	local lines = {}
	local task_list, other_tasks = M.get_tasks()
	local columnsWidth = get_columns_width(task_list, other_tasks, max_width)

	for _, task in ipairs(task_list) do
		local line = parse_line(task, columnsWidth)
		local hl = hl_normal
		utils.log_message("dashboard.M.get_lines", "task.urgency: " .. tonumber(task.urgency))
		if
			task.urgency ~= nil
			and M.config.highlights.urgent.threshold ~= nil
			and tonumber(task.urgency) >= M.config.highlights.urgent.threshold
		then
			utils.log_message("dashboard.M.get_lines", "Adding urgent line")
			table.insert(urgent_lines, line)
			hl = hl_overdue
		else
			utils.log_message("dashboard.M.get_lines", "Adding not urgent line")
			table.insert(not_urgent_lines, line)
		end
		table.insert(lines, { line .. "\n", hl = hl })
	end

	if #other_tasks > 0 and M.project and #task_list > 0 then
		table.insert(lines, { "--+--", hl = hl_normal, width = max_width - 1, align = "center" })
		table.insert(lines, { "\n", hl = hl_normal })
	end

	for _, task in ipairs(other_tasks) do
		local line = parse_line(task, columnsWidth)
		local hl = hl_normal
		utils.log_message("dashboard.M.get_lines", "task.urgency: " .. tonumber(task.urgency))
		if
			task.urgency ~= nil
			and M.config.highlights.urgent.threshold ~= nil
			and tonumber(task.urgency) >= M.config.highlights.urgent.threshold
		then
			utils.log_message("dashboard.M.get_lines", "Adding urgent line")
			table.insert(urgent_lines, line)
			hl = hl_overdue
		else
			utils.log_message("dashboard.M.get_lines", "Adding not urgent line")
			table.insert(not_urgent_lines, line)
		end
		table.insert(lines, { line .. "\n", hl = hl })
	end

	utils.log_message("dashboard.M.get_lines", vim.inspect(lines))

	return lines
end
--- Gets default highlight groups
--- @param which string (urgent|not_urgent) group name
--- @return table hl Highlight definition
local function get_default_hl_group(which)
	if which == "urgent" then
		local hl = vim.api.nvim_get_hl(0, { name = "@keyword" })
		return {
			bg = hl.bg,
			fg = hl.fg,
			cterm = hl.cterm,
			bold = hl.bold,
			italic = hl.italic,
			reverse = hl.reverse,
		}
	elseif which == "not_urgent" then
		local hl = vim.api.nvim_get_hl(0, { name = "Comment" })
		return {
			bg = hl.bg,
			fg = hl.fg,
			cterm = hl.cterm,
			bold = hl.bold,
			italic = hl.italic,
			reverse = hl.reverse,
		}
	else
		return {
			italic = true,
		}
	end
end

local function setup_hl_groups()
	local hl_urgent = nil
	if M.config.highlights and M.config.highlights.urgent and M.config.highlights.urgent.group then
		hl_urgent = M.config.highlights.urgent.group
	else
		hl_urgent = get_default_hl_group("urgent")
	end
	if hl_urgent then
		vim.api.nvim_set_hl(0, "TFDashboardHeaderUrgent", hl_urgent)
	end
	local hl_not_urgent = nil

	if M.config.highlights and M.config.highlights.normal and M.config.highlights.normal.group then
		hl_not_urgent = M.config.highlights.normal.group
	else
		hl_not_urgent = get_default_hl_group("not_urgent")
	end
	if hl_not_urgent then
		vim.api.nvim_set_hl(0, "TFDashboardHeader", hl_not_urgent)
	end
end

local function hl_tasks()
	setup_hl_groups()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	utils.log_message("dashboard.hl_tasks", "Lines: " .. vim.inspect(urgent_lines))
	for i, line in ipairs(lines) do
		if utils.in_table(urgent_lines, line) then
			vim.api.nvim_buf_add_highlight(0, -1, "TFDashboardHeaderUrgent", i - 1, 0, -1)
		elseif utils.in_table(not_urgent_lines, line) then
			vim.api.nvim_buf_add_highlight(0, -1, "TFDashboardHeader", i - 1, 0, -1)
		end
	end
end

function M.get_snacks_dashboard_tasks()
	local section = {}
	section.icon = M.config.dashboard.snacks_options.icon
	section.title = M.config.dashboard.snacks_options.title
	if M.config.dashboard.snacks_options.pane then
		section.pane = M.config.dashboard.snacks_options.pane
	end
	section.padding = M.config.dashboard.snacks_options.padding
	section.indent = M.config.dashboard.snacks_options.indent
	section.text = M.get_lines_for_snacks()
	section.height = M.config.dashboard.snacks_options.height
		or #section.text + M.config.dashboard.snacks_options.padding + 1
	print(vim.inspect(section))
	return section
end

function M.setup(user_config)
	utils.log_message("dashboard.M.setup", "Setting up Dashboard")
	M.config = vim.tbl_deep_extend("force", M.config, user_config or {})
	M.project = get_project()
	vim.api.nvim_create_autocmd("User", {
		pattern = "DashboardLoaded",
		callback = hl_tasks,
	})
	-- vim.api.nvim_create_autocmd({ "BufWipeout" }, {
	-- 	buffer = 0, -- Use 0 to apply to the current buffer
	-- 	callback = function()
	-- 		if vim.api.nvim_get_current_buf() == dashboard_bffnr then
	-- 			clear_dashboard_highlight()
	-- 		end
	-- 	end,
	-- })
end

return M

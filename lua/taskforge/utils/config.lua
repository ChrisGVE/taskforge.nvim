-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--

-- Default configuration structure
---@class TaskforgeOptions
local Config = {
  -- debug hook
  debug = {
    enable = nil,
    log_file = nil,
    log_max_len = nil,
  },
  -- Project naming configuration
  project = {
    -- project prefix, will be separated by a dot with the project name
    prefix = "",
    -- default project name for situations where the tagged files do not belong to an identified project
    default_project = "project",
    -- indicate whether the postfix is made by the path of the tagged file, the filename of the tagged file or both
    postfix = "PATH|FILENAME",
    -- default separator, path components are replaced with this separator
    separator = ".",

    -- project root heuristic
    detection_methods = { "lsp", "pattern" },
    -- project root pattern (order)
    root_patterns = {
      extensions = { -- extensions file which file name are the project name
        ".csproj", -- .NET project name
        ".xcodeproj", -- Xcode project name
      },
      signature = { -- existence of a file or a folder in the root folder which is the project name
        ".git", -- git repository
        "_darcs", -- darc repository
        ".hg", -- mercurial repository
        ".bzr", -- bazaar repository
        ".svn", -- subversion repository
        "Makefile",
      },
      json = { -- json file which contains information about the project including its name
        "project.json",
        "package.json",
      },
      exclude_dirs = { -- folders which should be excluded from the search (hence the project name would fall back to its default)
      },
    },
    -- extract project name from json file
    json_tags = { "project", "name" },
    -- project info file
    project_info = ".taskforge.json",
    -- remove any extension from the project name
    remove_extension = true,
    project_synonyms = {},
  },

  -- Tag tracking configuration
  tags = {
    -- enable tag tracking
    enable = true,
    -- auto refresh the task list for the current project
    auto_refresh = true,
    -- require confirmation for ask and manual, if set to false ask will behave like auto and manual won't require a confirmation
    confirmation = true,
    -- languages for which the plugin is active
    enabled_ft = {
      "*",
      -- "c",
      -- "cpp",
      -- "go",
      -- "hjson",
      -- "java",
      -- "javascript",
      -- "lua",
      -- "markdown",
      -- "python",
      -- "rust",
      -- "typescript",
      -- "zig",
    },
    --
    debounce = 500, -- time in ms to wait before updating taskwarrior after a change
    definitions = {
      -- format of the tags
      tag_format = ".*:",
      ["TODO"] = {
        priority = "M", -- default taskwarrior priority
        tags = { "coding", "enhancement" }, -- default taskwarrior tags
        due = "+1w", -- due date relative to the creation date
        alt = {}, -- alternative tags
        create = "ask", -- ask|auto|manual  action when the tag is created
        -- ask: the plugin will ask the user if a task should be created
        -- auto: a task will be auto created
        -- manual: a notification will be displayed to remind the user to create a task
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
    --- function to reload dashboard config
    get_dashboard_config = nil,
    -- Options for Snacks.nvim dashboard
    snacks_options = {
      key = "t",
      action = "taskwarrior-tui", -- "taskwarrior-tui"|"project"|"tasks"
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
      max_width = 55,
      -- Columns to be shown
      columns = {
        "id",
        "project",
        "description",
        "due",
        "urgency",
      },
      -- Abbreviations to shorten project names
      project_abbreviations = {},
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

function Config:setup(options)
  local new_config = vim.tbl_deep_extend("force", self, options)
  for key, value in pairs(new_config) do
    self[key] = value
  end
end

return Config

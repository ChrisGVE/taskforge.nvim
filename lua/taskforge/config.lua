-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License
--

-- Default configuration structure
local M = {
  _defaults = {
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
      -- indicate whether the postfix is made by the path of the tagged file, the filename of the tagged file,
      -- the extension, or a combination using the PIPE
      postfix = "PATH|FILENAME|EXT",
      -- default separator, path components are replaced with this separator, and all elements composing the taskwarrior
      -- project
      separator = ".",

      -- project root heuristic
      detection_methods = { lsp = true, pattern = true, vcs = true },
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
      -- remove any extension from the project name
      remove_extension = true,
      -- allows to map a project name if the identified project name is one of the synonyms
      project_synonyms = { taskforge = { "taskforge-v1", "taskforge-v2" } },
    },

    -- Tag tracking configuration
    tags = {
      -- enable tag tracking
      enable = true,
      -- auto refresh the task list for the current project
      auto_refresh = true,
      -- require confirmation for ask and manual, if set to false ask will behave like auto and manual won't require a confirmation
      confirmation = true,
      -- languages for which the plugin is active (only languages that are supported by treesitter)
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
        tag_format = "\\s*\\(.*\\):",
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
      format = {
        -- List of columns to be displayed
        columns = {
          "project",
          "description",
          "due",
          "urgency",
        },
        -- patterns that are replaced with abbreviations to shortened the lines
        project_abbreviations = {
          ["neovim."] = "nvim.",
          ["config."] = "cfg.",
          ["python."] = "py.",
          ["fountains."] = "f.",
          ["devtools."] = "dev.",
          ["wezterm."] = "wzt.",
          ["work."] = "wk.",
          ["personal."] = "p.",
        },
        shorten_sections = false, -- when true the project section names are summarized by their first letter. eg abc.fgh.zsy becomes a.f.zsy
        max_width = 55, -- maximum width of a task line
      },
    },
  },

  -- Task interface configuration
  interface = {
    keymaps = {
      open = "o", -- if the task is linked to a comment tag, opens the file (or change buffer if loaded) and jumps to the tag
      edit = "e", -- edit function via nvim
      close_task = "d", -- d for done
      modify_task = "m", -- similar to taskwarrior-tui: opens a line where the user can make changes
      annotate_task = "a", -- similar to taskwarrior-tui: opens a line to let the user add an annotation
      add_task = "+", -- similar to taskwarrior-tui: opens a line where the user can add a task
      delete_task = "-", -- unlike done it removes the task
      filter = "/", -- filter tasks
      sort = "s", -- select column(s) for sorting
      quit = "q", -- close the interface
      toggle_view = "t", -- toggle view between list and tree
      select_task = "v", -- select one task -- when selected options such as done, modify, annotate, delete apply to all tasks
      select_all_task = "V", -- select all tasks (within the current filter)
      unselect = "<esc>", -- unselect all tasks
      up = { "k", "<Up>" }, -- move up the task selector
      down = { "j", "<Down>" }, -- move down the task selector
      project = "p", -- toggle filter for the current project
    },
    view = {
      default = "list", -- or "tree" for dependency view
      position = "right",
      width = 40,
      project = false, -- if true the interface always open with only the tasks related to the current project
    },
    -- Selection of the picker
    integrations = {
      snacks = true,
      telescope = false,
      fzf = false,
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

function M.set(user_opts)
  -- Merge user options with defaults
  if not M._settings then
    M._settings = vim.deepcopy(M._defaults)
  end
  M._settings = vim.tbl_deep_extend("force", M._settings, user_opts or {})

  -- Validate configuration
  -- local ok, err = pcall(M._validate, M._settings)
  -- if not ok then
  --   vim.notify("Invalid Taskforge config: " .. err, vim.log.levels.ERROR)
  -- end
end

function M._validate(settings)
  -- Type validation
  assert(type(settings.debug.enable) == "boolean", "debug.enable must be boolean")

  local valid_pickers = { "snacks", "telescope", "fzf", "native" }
  assert(
    vim.tbl_contains(valid_pickers, settings.picker),
    "Invalid picker type. Valid options: " .. table.concat(valid_pickers, ", ")
  )

  -- Project config validation
  assert(type(settings.project.default_project) == "string", "project.default_project must be string")

  -- Dashboard validation
  assert(#settings.dashboard.format.columns >= 1, "dashboard.columns must have at least one column")

  return true
end

function M.get()
  return M._settings or M._defaults
end

return M

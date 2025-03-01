# Modular Architecture for Taskforge Tag Tracking

To address your concerns about the complexity and maintainability of the tag tracking functionality, I propose restructuring the code into a more modular organization.

## Proposed Folder Structure

```
lua/taskforge/
├── init.lua                # Main entry point
├── config.lua              # Configuration management
├── commands.lua            # Command registration and handling
├── tasks.lua               # Task CRUD operations with taskwarrior
├── project.lua             # Project detection and management
├── utils.lua               # Shared utility functions
├── tracker/                # New folder for tracking functionality
│   ├── init.lua            # Entry point for tracker (exports and setup)
│   ├── core.lua            # Core tracking functionality
│   ├── buffer.lua          # Buffer processing and monitoring
│   ├── tags.lua            # Tag detection and processing
│   ├── uuid.lua            # UUID management and protection
│   ├── multiline.lua       # Multiline comment handling
│   ├── formatter.lua       # Formatter compatibility
│   └── ui.lua              # UI components for tag interaction
└── lang/                   # Language-specific handling
    ├── init.lua            # Language module loader
    ├── common.lua          # Shared language patterns
    ├── template.lua        # Template language file for future extension
    ├── lua.lua             # Lua-specific patterns
    ├── c.lua               # C/C++ specific patterns
    ├── python.lua          # Python-specific patterns
    └── ...                 # Other language modules
```

## Module Responsibilities

### tracker/init.lua

- Exposes the public API of the tracker module
- Loads and initializes all submodules
- Handles setup and autocommand registration

```lua
local M = {}

function M.setup()
  -- Load all required modules
  local core = require("taskforge.tracker.core")
  local buffer = require("taskforge.tracker.buffer")
  local tags = require("taskforge.tracker.tags")
  local formatter = require("taskforge.tracker.formatter")

  -- Initialize the modules
  core.setup()
  buffer.setup()
  formatter.setup()

  -- Register commands
  M.register_commands()

  -- Export public API
  M.process_buffer = buffer.process
  M.process_all_comments = buffer.process_all
  M.add_tag_at_cursor = tags.add_at_cursor
  M.remove_tag_at_cursor = tags.remove_at_cursor
  M.link_tag_to_task = tags.link_to_task
  M.add_optout_at_cursor = tags.add_optout_at_cursor

  return M
end

-- Other functions...

return M
```

### tracker/core.lua

- Maintains the core state and cache for tracker
- Loads task data from taskwarrior
- Implements the debounce mechanism
- Tracks processed buffers

### tracker/buffer.lua

- Handles buffer processing logic
- Detects changes in buffer content
- Manages buffer events (enter, leave, etc.)
- Coordinates with other modules for processing

### tracker/tags.lua

- Implements tag detection and handling
- Processes tags based on their configuration
- Contains tag-specific CRUD operations

### tracker/uuid.lua

- Manages UUID tracking and linking
- Handles UUID protection and verification
- Implements restoration of modified UUIDs

### tracker/multiline.lua

- Detects and processes multiline comments
- Extracts tag information from multiline comments
- Adds UUIDs to multiline comments

### tracker/formatter.lua

-

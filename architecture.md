# Modular Architecture for Taskforge

This document outlines the architecture for Taskforge, a Neovim plugin for task management integrated with Taskwarrior. The design focuses on modularity, maintainability, and extensibility.

## Folder Structure

```
lua/taskforge/
├── init.lua                # Main entry point
├── config.lua              # Configuration management
├── commands.lua            # Command registration and handling
├── tasks.lua               # Task CRUD operations with taskwarrior
├── project.lua             # Project detection and management
├── utils/                  # Utility functions
│   ├── init.lua            # Main utils exports
│   ├── buffer.lua          # Buffer utilities
│   ├── events.lua          # Event management
│   └── ui/                 # UI utilities
│       ├── dialog.lua      # Generalized dialog component
│       ├── help.lua        # Help system
│       ├── components.lua  # Reusable UI components
│       ├── icons.lua       # Icon management
│       └── theme.lua       # Theming and styling
├── tracker/                # Tag tracking functionality
│   ├── init.lua            # Entry point for tracker
│   ├── core.lua            # Core tracking functionality and state
│   ├── buffer.lua          # Buffer processing and monitoring
│   ├── tags.lua            # Tag detection and processing
│   ├── uuid.lua            # UUID management and protection
│   ├── multiline.lua       # Multiline comment handling
│   └── formatter.lua       # Formatter compatibility
├── interface/              # Main task interface
│   ├── init.lua            # Interface entry point
│   ├── tree.lua            # Dependency tree view
│   └── list.lua            # Task list view
├── dashboard.lua           # Dashboard integration
├── lang/                   # Language-specific handling
│   ├── init.lua            # Language module loader
│   ├── common.lua          # Shared language patterns and functionality
│   ├── template.lua        # Template language file for future extension
│   ├── lua.lua             # Lua-specific patterns
│   └── ...                 # Other language modules
└── integrations/           # External plugin integrations
    ├── trouble.lua         # Trouble.nvim integration
    └── ...                 # Other integrations
```

## Core Modules

### init.lua

- Plugin entry point and setup
- Dependency checking and initialization
- Public API for other plugins

### config.lua

- Configuration management with defaults
- User settings validation
- Configuration utilities

### commands.lua

- Registration of all user commands
- Command dispatch logic
- Command completion helpers

### tasks.lua

- Taskwarrior integration
- CRUD operations for tasks
- Task caching and management

### project.lua

- Project detection using multiple methods (LSP, VCS, patterns)
- Project name formatting and management
- File-to-project mapping

## Utility Modules

### utils/

This directory contains general utility functions used across the plugin:

#### buffer.lua

- Buffer management utilities
- Safe processing to prevent recursion
- Content extraction and manipulation

#### events.lua

- Event management system
- Centralized event registration
- Debouncing mechanism

#### ui/dialog.lua

- Generalized dialog adapter for different picker backends
- Supports structured data with columns
- Buffer-aware navigation capabilities
- Toggle functionality with customizable icons
- Theming support

#### ui/help.lua

- Context-sensitive help system
- Integrates with dialog system
- Displays relevant keymaps and descriptions

#### ui/components.lua

- Reusable UI building blocks
- Lists, selectors, headers, footers
- Shared across different interfaces

#### ui/icons.lua and ui/theme.lua

- Icon management and theming systems
- Adapts to user's Neovim configuration

## Tracker Module

The tracker module manages code comment tags and their association with Taskwarrior tasks.

### tracker/init.lua

- Public API for the tracker system
- Module initialization and event setup
- Command registration for tag operations

### tracker/core.lua

- Centralized state management
- Debounce mechanism for edits
- Task-to-location mapping
- Common utilities for tag handling

### tracker/buffer.lua

- Buffer processing for tag detection
- TreeSitter integration for comment finding
- Tag highlighting and annotation
- Tag processing based on configuration

### tracker/tags.lua

- Tag processing logic
- Task creation, update, and deletion
- Tag-specific behavior definition
- Tag-to-task relationship management

### tracker/uuid.lua

- UUID management for tag-task links
- UUID format protection and repair
- UUID storage and retrieval

### tracker/multiline.lua

- Multiline comment detection and processing
- Block comment handling
- Language-specific multiline tags

### tracker/formatter.lua

- Integration with code formatters
- UUID preservation during formatting
- Post-formatting repair mechanisms

## Interface Module

The interface module provides the main task management interface.

### interface/init.lua

- Main interface entry point
- Interface initialization and setup
- Picker integration

### interface/tree.lua

- Dependency tree visualization
- Hierarchical task display
- Parent-child relationship management

### interface/list.lua

- Flat task list view
- Sorting and filtering
- Task detail display

## Language Module

The language module provides language-specific functionality for comment detection and tag handling.

### lang/init.lua

- Language module loader and dispatcher
- Filetype detection and mapping
- Language support determination

### lang/common.lua

- Shared language patterns and utilities
- Fallback implementations for unsupported languages
- Common comment handling logic

### lang/template.lua

- Template for language-specific modules
- Documentation of required functions
- Example implementations

### lang/\* (language-specific modules)

- Language-specific comment detection
- Custom tag parsing rules
- Specialized UUID placement logic

## Integrations Module

The integrations module provides compatibility with external Neovim plugins.

### integrations/trouble.lua

- Integration with Trouble.nvim
- Displays tracked tasks in Trouble interface
- Supports navigation to task locations

## Architecture Principles

1. **Separation of Concerns**: Each module has a clear, focused responsibility
2. **Composition Over Inheritance**: Modules work together through well-defined interfaces
3. **Progressive Enhancement**: Core functionality works without optional dependencies
4. **Configuration Over Convention**: Behavior is configurable while providing sensible defaults
5. **Error Resilience**: Graceful handling of errors and edge cases

## Event Flow

### Tag Tracking

1. When a buffer is opened:

   - `BufEnter` event triggers `tracker.init`
   - Tracker initializes buffer tracking through `buffer.lua`
   - Buffer is processed for existing tags

2. During editing:

   - Edit events trigger debounce through `core.lua`
   - After debounce period, buffer is re-processed
   - New tags are detected and processed based on configuration

3. When a tag is detected:

   - Configuration determines behavior (auto/ask/manual)
   - For "auto" tags, tasks are created automatically
   - For "ask" tags, UI prompts for confirmation
   - For "manual" tags, a notification is displayed

4. When a task status changes:
   - Changes propagate through tag tracking system
   - Tags in code are updated or removed as configured
   - Visual indicators reflect current status

### Dialog System Flow

1. Dialog Creation:

   - Dialog adapter initializes based on configuration
   - Selects appropriate picker backend
   - Configures view based on caller requirements

2. User Interaction:

   - Key events trigger configured callbacks
   - Row selection navigates buffer to corresponding location
   - Toggle actions update selection state

3. Dialog Completion:
   - Results passed back to caller based on selected mode
   - Resources properly cleaned up
   - Focus returned to appropriate context

## Implementation Priorities

1. ✅ Core functionality (tasks, project, commands)
2. ✅ Tag tracking system (detection, task creation, tracking)
3. ✅ Formatter compatibility and UUID protection
4. 🔄 UI component refactoring and dialog generalization
5. 🔄 Language-specific modules for better comment support
6. 📋 Task management interface implementation
7. 📋 Dashboard integration refinement
8. 📋 Documentation and testing

This architecture document will be updated as the project evolves to reflect current design decisions and future plans.

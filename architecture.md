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
├── utils.lua               # Shared utility functions
├── dashboard.lua           # Dashboard integration (for snacks.dashboard)
├── picker.lua              # Unified picker interface for tasks
├── interface.lua           # Task management interface
├── tracker/                # Tag tracking functionality
│   ├── init.lua            # Entry point for tracker (exports and setup)
│   ├── core.lua            # Core tracking functionality and state
│   ├── buffer.lua          # Buffer processing and monitoring
│   ├── tags.lua            # Tag detection and processing
│   ├── uuid.lua            # UUID management and protection
│   ├── multiline.lua       # Multiline comment handling
│   └── formatter.lua       # Formatter compatibility
├── ui/                     # UI components and utilities (planned)
│   ├── init.lua            # Main UI exports and setup
│   ├── utils.lua           # Position, size and other utilities
│   ├── dialog.lua          # Generic dialog component
│   ├── help.lua            # Help dialog component
│   ├── batch.lua           # Batch processing dialog
│   ├── icons.lua           # Icon management and loading
│   ├── theme.lua           # Colors and styling
│   └── components/         # For future specialized components
│       ├── list.lua        # Reusable list component
│       ├── tabs.lua        # Tab component for complex views
│       └── form.lua        # Form inputs for task creation/editing
└── lang/                   # Language-specific handling
    ├── init.lua            # Language module loader
    ├── common.lua          # Shared language patterns and functionality
    ├── template.lua        # Template language file for future extension
    ├── lua.lua             # Lua-specific patterns
    ├── c.lua               # C/C++ specific patterns
    ├── python.lua          # Python-specific patterns
    └── ...                 # Other language modules
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

### utils.lua

- Shared utility functions
- Logging and notification helpers
- File and text manipulation utilities

### dashboard.lua

- Integration with snacks.dashboard
- Task display and formatting for dashboard
- Dashboard section management

### picker.lua

- Unified interface for task selection
- Support for multiple backends (snacks.picker, telescope, fzf)
- Task formatting for pickers

### interface.lua

- Task management interface
- Task tree visualization using nui.nvim
- Task details and operations

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

## UI Module (Planned)

The UI module will provide reusable components for all user interfaces in Taskforge.

### ui/init.lua

- UI module initialization
- Registration of UI components
- Event setup for UI interactions

### ui/utils.lua

- Size and position calculations
- Common UI helper functions
- Window and buffer utilities

### ui/dialog.lua

- Generic dialog foundation
- Common dialog behaviors
- Standard dialog lifecycle and events

### ui/help.lua

- Help dialog implementation
- Customizable help content
- Help UI styling and keymaps

### ui/batch.lua

- Batch processing dialog for tags
- Tag selection and management UI
- Source highlighting and navigation

### ui/icons.lua

- Icon loading and management
- Support for multiple icon sources
- Icon rendering utilities

### ui/theme.lua

- Colors and styling system
- Highlight group management
- Theme integration with Neovim

### ui/components/\*

- Specialized UI components
- Reusable elements (lists, forms, tabs)
- Building blocks for complex interfaces

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

### UI Components Flow

1. Dialog Creation:

   - Generic dialog base provides common functionality
   - Specialized dialogs extend with specific behavior
   - Dialog state is managed within the component

2. User Interaction:

   - Events are processed through standard handlers
   - Actions trigger callbacks to business logic
   - State updates cause UI refreshes

3. Dialog Completion:
   - Results are passed to provided callbacks
   - Resources are properly cleaned up
   - Focus is returned to appropriate context

## Implementation Priorities

1. ✅ Core functionality (tasks, project, commands)
2. ✅ Tag tracking system (detection, task creation, tracking)
3. ✅ Formatter compatibility and UUID protection
4. 🔄 UI component refactoring and improvements
5. 🔄 Language-specific modules for better comment support
6. 📋 Full task management interface and dashboard integration
7. 📋 Documentation and testing

## Future Enhancements

1. LSP integration for improved language detection
2. File operation tracking using LSP
3. Additional language-specific modules
4. Enhanced formatter compatibility with additional formatters
5. Improved multiline comment handling for complex syntaxes
6. Advanced project management features
7. Richer task visualization and reporting

---

This architecture document will be updated as the project evolves to reflect current design decisions and future plans.

# Modular Architecture for Taskforge Tag Tracking

This document outlines the architecture for the refactored Taskforge tag tracking system. The goal is to improve maintainability, extensibility, and performance by breaking down the monolithic tracker into specialized modules.

## Folder Structure

```
lua/taskforge/
├── init.lua                # Main entry point
├── config.lua              # Configuration management
├── commands.lua            # Command registration and handling
├── tasks.lua               # Task CRUD operations with taskwarrior
├── project.lua             # Project detection and management
├── utils.lua               # Shared utility functions
├── tracker/                # Tag tracking functionality
│   ├── init.lua            # Entry point for tracker (exports and setup)
│   ├── core.lua            # Core tracking functionality and state
│   ├── buffer.lua          # Buffer processing and monitoring
│   ├── tags.lua            # Tag detection and processing
│   ├── uuid.lua            # UUID management and protection
│   ├── multiline.lua       # Multiline comment handling
│   ├── formatter.lua       # Formatter compatibility
│   └── ui.lua              # UI components for tag interaction
└── lang/                   # Language-specific handling
    ├── init.lua            # Language module loader
    ├── common.lua          # Shared language patterns and functionality
    ├── template.lua        # Template language file for future extension
    ├── lua.lua             # Lua-specific patterns
    ├── c.lua               # C/C++ specific patterns
    ├── python.lua          # Python-specific patterns
    └── ...                 # Other language modules
```

## Module Responsibilities

### tracker/init.lua

- Serves as the public API for the tracker system
- Initializes all tracker submodules
- Sets up autocommands for buffer events
- Provides a clean interface for other parts of the plugin
- Maintains global state for the tracker system
- Manages the edit state and debounce mechanism

```lua
-- Example public API
local M = {
  process_buffer = function(bufnr) ... end,
  add_tag_at_cursor = function() ... end,
  remove_tag_at_cursor = function() ... end,
  ...
}
```

### tracker/core.lua

- Maintains the core state and cache for tracking
- Provides a centralized data store for tracker information
- Implements the debounce mechanism for handling edits
- Loads and updates task information from taskwarrior
- Manages buffer processing state
- Handles basic UUID operations
- Provides utilities for tag data manipulation

### tracker/buffer.lua

- Processes buffers to detect and handle tag comments
- Uses TreeSitter for precise comment detection
- Creates, modifies, and removes comment markers
- Handles buffer change events
- Coordinates with other modules for tag processing
- Performs batch processing of multiple tags
- Manages highlighting and visual indicators for tags

### tracker/tags.lua

- Implements tag detection and handling logic
- Processes tags based on their configuration
- Creates tasks based on tag information
- Handles tag removal and task completion
- Manages tag-specific attributes
- Processes tracked tags vs. untracked tags
- Handles task linking/unlinking for comments

### tracker/uuid.lua

- Manages UUID tracking and linking
- Handles UUID protection and verification
- Restores modified UUIDs when necessary
- Adds/removes UUIDs from comments
- Detects UUID changes in comments
- Provides utilities for UUID format handling
- Manages the linking between comments and tasks

### tracker/multiline.lua

- Handles multiline comment detection and processing
- Extracts tag information from multiline comments
- Adds UUIDs to multiline comments properly
- Processes comment blocks with language-specific syntax
- Manages comment context detection
- Provides utilities for working with multi-line code structures
- Coordinates with language modules for syntax accuracy

### tracker/formatter.lua

- Handles compatibility with code formatters
- Detects formatting operations
- Preserves UUIDs during formatting
- Repairs damaged UUIDs after formatting
- Hooks into popular formatter events
- Manages pre/post format state
- Provides integration with LSP formatting

### tracker/ui.lua

- Implements UI components for tag interaction
- Provides batch processing UI for multiple tags
- Manages selection and confirmation dialogs
- Handles tag navigation within buffers
- Shows tag information and details
- Integrates with nui.nvim for richer UI elements
- Provides popup notifications and confirmations

### lang/init.lua

- Serves as the loader for language-specific modules
- Detects the appropriate language module for a buffer
- Provides fallback to common module when needed
- Caches language modules for performance
- Interfaces with LSP for enhanced language detection
- Manages language module selection based on filetype
- Provides common utilities for all language modules

### lang/common.lua

- Implements shared language patterns and behavior
- Provides fallback functionality for unsupported languages
- Defines common comment detection mechanisms
- Implements generic tag extraction patterns
- Handles basic UUID insertion in comments
- Provides utilities for working with comments across languages
- Defines interface that all language modules implement

### lang/template.lua

- Serves as a template for new language modules
- Demonstrates required functions and patterns
- Shows examples of language-specific customization
- Documents the language module interface
- Provides a starting point for language contributors
- Includes well-documented examples

### lang/lua.lua (and other language modules)

- Implements language-specific patterns and behavior
- Provides accurate comment detection for the language
- Implements proper UUID insertion for language syntax
- Handles language-specific comment patterns
- Manages block comments for the language
- Provides optimized tag extraction for the language
- Handles language-specific edge cases

## Integration Strategy

1. Replace the current `tracker.lua` implementation with the new modular system
2. Ensure backward compatibility for existing API calls
3. Gradually improve each module based on testing and user feedback
4. Add language modules prioritizing the most commonly used languages

## Future Enhancements

1. Add LSP integration for improved language detection
2. Implement file operation tracking using LSP
3. Add more language-specific modules
4. Enhance formatter compatibility with additional formatters
5. Improve multiline comment handling for complex syntaxes

## Tracker Event Flow

1. Buffer is opened → `BufEnter` event
2. `tracker/init.lua` catches event and calls `buffer.process()`
3. `buffer.lua` uses TreeSitter to detect comments
4. For each comment, relevant modules process tags:
   - New tags → `tags.lua` processes them based on configuration
   - Existing UUIDs → `uuid.lua` verifies and updates if needed
   - Multiline comments → `multiline.lua` handles specially
5. Buffer is edited → text change events trigger debounce timer
6. After debounce period, buffer is processed again
7. Code is formatted → `formatter.lua` handles UUID preservation
8. Tag is modified → `uuid.lua` offers to restore if needed
9. Task is completed → `tags.lua` updates the comment accordingly

This architecture provides a scalable and maintainable foundation for the tag tracking system while ensuring all the requirements are met efficiently.

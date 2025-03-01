# Taskforge Tag Tracking

Taskforge provides comprehensive tracking of code comments with tags like `TODO`, `FIXME`, `BUG`, and other configurable tags. This document explains how the tag tracking system works and how to use it effectively.

## Basic Features

### Tag Detection

The plugin automatically detects comment tags in your code and offers to create Taskwarrior tasks for them. Each type of tag can be configured with specific behaviors:

- `auto` - Tasks are created automatically without user intervention
- `ask` - The plugin asks for confirmation before creating tasks
- `manual` - The plugin notifies you about the tags but doesn't create tasks automatically

Once a task is created, a unique identifier (UUID) is inserted into the comment to link it with the Taskwarrior task.

### Tracked Comments Format

When a comment is tracked, Taskforge adds a UUID marker to link it with a Taskwarrior task:

```lua
-- TODO: Implement feature X [task:12345678-90ab-cdef-1234-567890abcdef]
```

### Multiline Comment Support

Taskforge supports both single-line and multiline comments:

```lua
--[[
TODO: Implement feature X
This is a longer description
spanning multiple lines
]] -- [task:12345678-90ab-cdef-1234-567890abcdef]
```

### Opt-out Mechanism

If you have comments with tags that you don't want to track, you can add the `[notrack]` marker:

```lua
-- TODO: Just a reminder, don't create a task [notrack]
```

## Commands

### `:TaskforgeTag add`

Adds a tag to the current line or creates a task for an existing tag at the cursor position.

### `:TaskforgeTag remove`

Removes a tag from the current line and optionally marks the associated task as done.

### `:TaskforgeTag link`

Manually links an existing task to a comment at the cursor position.

### `:TaskforgeTag optout`

Adds the `[notrack]` marker to a comment to prevent task creation.

### `:TaskforgeTag process`

Scans the current file for all untracked tags and processes them according to their configuration.

## Multiple Tag Processing

When opening a file that contains multiple untracked tags, you can use `:TaskforgeTag process` to handle them all at once:

1. Tags configured for automatic creation will be processed silently
2. Tags configured for manual creation will generate notifications
3. Tags configured to ask for confirmation will be presented in an interactive list

## Smart Debouncing

The plugin implements smart debouncing during editing:

- While you're actively editing text, tag detection is temporarily suspended
- After you stop typing for the configured debounce period, tags are processed
- This prevents disruption during editing while ensuring tags are handled promptly

## UUID Protection

The UUID that links comments to tasks is protected:

- If you accidentally modify or delete the UUID, the plugin will detect this
- You'll be prompted to restore the original UUID format
- This ensures the link between your code and Taskwarrior tasks remains intact

## Formatter Compatibility

The plugin is compatible with code formatters:

- After formatting operations, taskforge checks if any UUIDs were affected
- Any formatting issues that might break task links are automatically fixed
- This ensures compatibility with tools like `conform.nvim`, `null-ls`, and other formatters

## Task Status Management

When you mark a task as done in Taskwarrior, the plugin can:

1. Remove the tag from the comment
2. Replace the tag with `DONE:`
3. Remove the entire comment line

This behavior is configurable in the plugin settings.

## Multiple File Management

Taskforge handles file operations correctly:

- If a file is renamed or moved, task annotations are updated
- If comments move to different lines during editing, the links remain intact
- The plugin uses a combination of LSP events and heuristics to maintain correct tracking

## Configuration Example

Here's an example configuration for tag tracking:

```lua
{
  tags = {
    enable = true,
    auto_refresh = true,
    confirmation = true,
    enabled_ft = { "*" },
    debounce = 500,
    definitions = {
      ["TODO"] = {
        priority = "M",
        tags = { "coding", "enhancement" },
        due = "+1w",
        alt = {},
        create = "ask",
        close = "auto",
      },
      ["FIXME"] = {
        priority = "H",
        tags = { "coding", "bug" },
        due = "+2d",
        alt = { "FIX", "BUG" },
        create = "auto",
        close = "auto",
      },
    },
  },
}
```

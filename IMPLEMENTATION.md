# Taskforge Implementation Guide

## 1. Core Functionality Implementation

### 1.1 Dialog System

The dialog system needs to be generalized to provide a flexible foundation for all user interfaces:

```lua
-- Interface for dialog options
{
  -- Content parameters
  title = "Dialog Title",           -- Title shown in border
  columns = {                       -- Column definitions
    { id = "select", width = 4 },
    { id = "tag", width = 8 },
    { id = "description", width = 30 },
  },
  data = {...},                     -- Data items to display

  -- Appearance
  position = {                      -- Position relative to source window
    row = "top",                    -- "top", "center", "bottom" or number
    col = "center",                 -- "left", "center", "right" or number
  },
  size = {                          -- Size constraints
    width_percent = 80,             -- Percentage of window width
    height_percent = 20,            -- Percentage of window height
    min_width = 40,                 -- Minimum width
    min_height = 10,                -- Minimum height
  },

  -- Behavior
  source_bufnr = bufnr,             -- Source buffer for navigation
  keymaps = {                       -- Keyboard mappings
    ["<CR>"] = function(dialog) end,
    ["q"] = function(dialog) end,
  },

  -- Callbacks
  on_select = function(item) end,   -- Item selection callback
  on_highlight = function(item) end, -- Item highlighting callback
  on_complete = function(items) end, -- Dialog completion callback

  -- Optional features
  enable_filter = true,             -- Enable filtering
  enable_sort = true,               -- Enable sorting
  enable_search = true,             -- Enable fuzzy search

  -- Help content
  help_content = {                  -- Help text to display
    title = "Help Dialog",
    sections = {...}
  }
}
```

### 1.2 Tag Tracking

The tag tracking system should implement these behaviors:

1. **Smart Debouncing**:

   ```lua
   -- Monitor editing activity
   vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
     callback = function(event)
       -- Mark editing as active
       tracker.state.edit_active = true
       -- Reset debounce timer
       tracker.reset_debounce_timer(event.buf)
     end
   })

   -- Process after editing stops
   vim.api.nvim_create_autocmd({"InsertLeave"}, {
     callback = function(event)
       -- Mark editing as inactive
       tracker.state.edit_active = false
     end
   })
   ```

2. **UUID Protection**:

   ```lua
   -- Verify and fix UUID format
   function verify_uuid_format(line, uuid)
     local original_marker = "[task:" .. uuid .. "]"
     -- Check if line contains exactly this marker
     if not line:match(escape_pattern(original_marker)) then
       -- Prompt user to restore the correct format
       prompt_restore_uuid(line, uuid)
     end
   end
   ```

3. **Formatter Compatibility**:

   ```lua
   -- Hook into formatting events
   vim.api.nvim_create_autocmd({"BufWritePre"}, {
     callback = function(event)
       -- Store current UUIDs before formatting
       store_buffer_uuids(event.buf)
     end
   })

   vim.api.nvim_create_autocmd({"BufWritePost"}, {
     callback = function(event)
       -- Check and restore UUIDs after formatting
       check_and_restore_uuids(event.buf)
     end
   })
   ```

## 2. UI Implementation

### 2.1 Component Consolidation

The UI components should be consolidated into a single file:

```lua
-- components.lua will include:

-- List component
M.create_list = function(options)
  -- Create scrollable, selectable list
end

-- Form component
M.create_form = function(options)
  -- Create form with inputs
end

-- Tree component
M.create_tree = function(options)
  -- Create hierarchical tree view
end

-- Tab component
M.create_tabs = function(options)
  -- Create tabbed interface
end
```

### 2.2 Help System

The help system should be generalized:

```lua
-- Help system options
{
  title = "Help Dialog",            -- Help title
  sections = {                      -- Content sections
    {
      title = "Navigation",
      content = {
        "j/k, Up/Down : Move selection",
        "Enter : Confirm selection"
      }
    },
    {
      title = "Actions",
      content = {
        "v : Toggle selection",
        "V : Toggle all"
      }
    }
  },
  keymaps = {                       -- Auto-close on any key
    ["<any>"] = function(help) help:close() end
  }
}
```

## 3. Batch Processing Implementation

The batch processing dialog should use the generalized dialog system:

```lua
-- Simplified batch.lua using generalized dialog
function process_batch_tags(bufnr, candidates)
  -- Categorize candidates
  local auto_tags, manual_tags, interactive_tags = categorize_tags(candidates)

  -- Process automatic tags
  process_auto_tags(bufnr, auto_tags)

  -- Notify about manual tags
  notify_manual_tags(bufnr, manual_tags)

  -- Show dialog for interactive tags
  if #interactive_tags > 0 then
    dialog.show({
      title = "Select Tags to Create",
      source_bufnr = bufnr,
      data = interactive_tags,
      columns = { "select", "tag", "description", "line" },
      on_complete = function(results)
        apply_tag_selections(bufnr, results)
      end
    })
  end
end
```

## 4. Language Module Improvements

Language modules should follow a consistent pattern:

```lua
-- Template for language modules
local M = {}

-- Required metadata
M.name = "language_name"
M.filetypes = { "filetype1", "filetype2" }

-- Comment pattern definitions
M.comment_patterns = {
  line_start = "//",
  block_start = "/*",
  block_end = "*/",
  -- Other language-specific patterns
}

-- Required functions
M.is_comment_string = function(line) ... end
M.extract_tag_info = function(comment_text, tag_name) ... end
M.detect_comment_context = function(bufnr, lnum) ... end
M.add_uuid_to_comment = function(comment_text, uuid) ... end

return M
```

## 5. Error Handling

Implement robust error handling throughout:

```lua
-- Protected function execution
function safely_execute(func, ...)
  local status, result = pcall(func, ...)
  if not status then
    log_error("Function execution failed: " .. tostring(result))
    notify_user("Operation failed: " .. get_friendly_error(result))
    return nil
  end
  return result
end

-- Health check
function check_health()
  local issues = {}

  -- Check dependencies
  if not has_dependency("plenary") then
    table.insert(issues, "Required dependency 'plenary.nvim' missing")
  end

  -- Check Taskwarrior
  if vim.fn.executable("task") ~= 1 then
    table.insert(issues, "Taskwarrior not found in PATH")
  end

  -- Check configuration
  local config_issues = validate_config(config.get())
  for _, issue in ipairs(config_issues) do
    table.insert(issues, issue)
  end

  return issues
end
```

## 6. Integration Testing

The implementation should be validated through these test scenarios:

1. **Comment Detection**:

   - Verify detection across supported languages
   - Test with various comment styles
   - Validate multiline comment handling

2. **Task Synchronization**:

   - Create tasks from comments
   - Update tasks when comments change
   - Remove tasks when comments are deleted
   - Handle task status changes

3. **UI Interactions**:

   - Test dialog with various data sets
   - Validate keyboard navigation
   - Check selection behavior
   - Verify buffer navigation integration

4. **Formatter Compatibility**:

   - Test with multiple formatters
   - Verify UUID preservation
   - Check restoration of damaged UUIDs

5. **Edge Cases**:
   - Handle very large files
   - Test with unicode characters
   - Verify behavior with malformed comments
   - Check performance with many tracked tasks

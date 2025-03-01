# Taskforge Tag Tracking Features Integration

This guide explains how to integrate the new tag tracking features into your Taskforge plugin. The implementation addresses the requirements for better tag detection and task management with Taskwarrior.

## Files to Add/Update

1. **`lua/taskforge/tracker.lua`**

   - This is the core module that handles tag detection, task creation, and tracking
   - Includes smart debouncing, UUID protection, and comment tracking

2. **`lua/taskforge/multiline.lua`**
   - New module to support multiline comment detection and processing
   - Works with different language syntax for block comments

## Integration Steps

1. **Place the files in your plugin directory**:

   - Copy `tracker.lua` to `lua/taskforge/`
   - Copy `multiline.lua` to `lua/taskforge/`

2. **Update your initialization in `init.lua`**:

   ```lua
   -- Add this to your setup function
   if M._available_deps.taskwarrior then
     -- Configure taskwarrior
     require("taskforge.tasks").configure()

     -- Initialize tracker module
     require("taskforge.tracker").setup()

     -- Set up commands
     require("taskforge.commands").register()
   end
   ```

3. **Update your configuration options in `config.lua`**:

   ```lua
   -- Add these options to your default configuration
   tags = {
     -- existing options...

     -- New options
     remove_on_done = true, -- Remove tag when task is completed
     remove_line_on_done = false, -- Remove entire line when task is completed
     optout_marker = "[notrack]", -- Marker for comments that should not be tracked
   },
   ```

4. **Register the new commands in `commands.lua`**:

   ```lua
   -- Update your cmd_tag function to handle the new commands
   function M.cmd_tag(args)
     if #args == 0 then
       utils.notify("Usage: Taskforge tag <add|remove|link|optout|process>", vim.log.levels.ERROR)
       return
     end

     local tracker = require("taskforge.tracker")
     local subcmd = args[1]

     if subcmd == "add" then
       tracker.add_tag_at_cursor()
     elseif subcmd == "remove" then
       tracker.remove_tag_at_cursor()
     elseif subcmd == "link" then
       tracker.link_tag_to_task()
     elseif subcmd == "optout" then
       tracker.add_optout_at_cursor()
     elseif subcmd == "process" then
       tracker.process_all_comments()
     else
       utils.notify("Unknown tag command: " .. subcmd, vim.log.levels.ERROR)
     end
   end
   ```

## Key Features Implemented

1. **Smart Debouncing**

   - Tag processing is paused during active editing
   - Processing resumes after editing stops for the configured debounce period

2. **UUID Protection**

   - Warns when UUIDs are modified and offers to restore them
   - Ensures task tracking remains intact even if comments are edited

3. **Multiline Comment Support**

   - Detects and processes tags in multiline comments across various languages
   - Properly handles block comment syntax for different file types

4. **Opt-out Mechanism**

   - Users can add `[notrack]` to comments to exclude them from tracking
   - Prevents unwanted task creation for certain comments

5. **Batch Processing**

   - New command `:TaskforgeTag process` to handle multiple tags in a file
   - Automatically processes tags based on their configuration

6. **Formatter Compatibility**
   - Includes hooks for popular formatters like conform.nvim
   - Automatically fixes any UUIDs affected by formatting

## Testing Your Integration

After integrating the new code:

1. Open a file with untracked TODO comments
2. Run `:TaskforgeTag process` to see batch processing in action
3. Try editing a comment with a UUID to test the protection feature
4. Format a file with a tracked comment to test formatter compatibility
5. Add a multiline comment with a tag and process it

## Common Issues

- If formatter hooks aren't working, ensure your formatter emits the appropriate events
- For LSP-based formatters, you may need to add custom events
- Test with different comment styles to ensure proper multiline support

---

These new features significantly enhance the tag tracking capabilities of Taskforge while improving the user experience. The implementation properly handles the edge cases mentioned in the requirements and adds smooth integration with code formatters.

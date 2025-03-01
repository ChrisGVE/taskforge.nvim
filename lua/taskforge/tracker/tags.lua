-- lua/taskforge/tracker/tags.lua
-- Tag detection and processing

local M = {}
local core = require("taskforge.tracker.core")
local utils = require("taskforge.utils")
local config = require("taskforge.config")

-- Process a tracked comment (with UUID)
function M.process_tracked_comment(bufnr, lnum, comment_text, uuid)
  local cfg = config.get()

  -- Check if task exists in cache
  if not core.get_task(uuid) then
    -- Try to get task from taskwarrior
    local tasks = require("taskforge.tasks")
    local task = tasks.get_task(uuid)

    if task then
      -- Update cache
      core.register_task(uuid, vim.api.nvim_buf_get_name(bufnr), lnum + 1, task.description, task.status)
    else
      -- Task might have been deleted
      utils.debug_log("TAGS", "UUID doesn't match any task", uuid)

      -- Warn user and offer to remove the UUID
      utils.confirm_yesno("Task " .. uuid .. " no longer exists. Remove UUID from comment?", function(choice)
        if choice == 1 then
          -- Remove UUID from comment
          local uuid_module = require("taskforge.tracker.uuid")
          uuid_module.remove_uuid_from_comment(bufnr, lnum, uuid)
          utils.notify("UUID removed from comment", vim.log.levels.INFO)
        end
      end)
      return
    end
  end

  -- Update task location in cache
  core.update_task_location(uuid, vim.api.nvim_buf_get_name(bufnr), lnum + 1)

  -- Check if UUID format is correct
  if not core.verify_uuid_format(comment_text, uuid) then
    -- UUID is present but in modified form
    local uuid_module = require("taskforge.tracker.uuid")
    uuid_module.handle_modified_uuid(bufnr, lnum, comment_text, uuid)
  end

  -- Cache the current comment state
  core.cache_tag(bufnr, lnum, {
    uuid = uuid,
    text = comment_text,
  })

  -- Find the tag that would have created this task
  local tag_found = false
  local tag_def = nil

  for tag, def in pairs(cfg.tags.definitions or {}) do
    -- Include alternative tags
    local tags_to_check = { tag }
    if def.alt then
      vim.list_extend(tags_to_check, def.alt)
    end

    for _, tag_name in ipairs(tags_to_check) do
      if comment_text:match(tag_name) then
        -- Add visual marker
        local buffer = require("taskforge.tracker.buffer")
        buffer.add_tag_marker(bufnr, lnum, tag_name)
        tag_found = true
        tag_def = def

        -- Update cache with tag definition
        local cached = core.get_cached_tag(bufnr, lnum)
        if cached then
          cached.tag_def = def
          cached.tag_name = tag_name
          core.cache_tag(bufnr, lnum, cached)
        end

        break
      end
    end

    if tag_found then
      break
    end
  end

  -- If no known tag found, use generic marker
  if not tag_found then
    local buffer = require("taskforge.tracker.buffer")
    buffer.add_tag_marker(bufnr, lnum, "TASK")
  end
end

-- Handle a detected tag without UUID
function M.process_tag(bufnr, lnum, tag, def, node, no_create)
  -- Extract description
  local lang = require("taskforge.lang").get_for_buffer(bufnr)
  local comment_text = vim.treesitter.get_node_text(node, bufnr)
  local info = lang.extract_tag_info(comment_text, tag)
  local desc = info and info.description or "No description"

  utils.debug_log("TAGS", "Extracted description", { tag = tag, description = desc })

  -- Store metadata
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local task_info = {
    description = tag .. ": " .. desc,
    file = file_path,
    line = lnum + 1,
    project = require("taskforge.project").current(),
    tags = def.tags,
    due = def.due,
    priority = def.priority,
  }

  -- Cache tag info
  core.cache_tag(bufnr, lnum, {
    text = comment_text,
    task_info = task_info,
    tag_name = tag,
    tag_def = def,
  })

  -- Add visual marker
  local buffer = require("taskforge.tracker.buffer")
  buffer.add_tag_marker(bufnr, lnum, tag)

  -- Don't create task if the no_create flag is set
  if no_create then
    return
  end

  -- Check if comment already has a UUID
  if comment_text:match(core.constants.uuid_pattern) then
    return
  end

  -- Check if comment has opted out
  if comment_text:match(core.constants.optout_pattern) then
    return
  end

  -- Create task based on configuration
  if def.create == "auto" then
    utils.debug_log("TAGS", "Auto-creating task for tag", tag)
    M.create_task_for_tag(bufnr, lnum, task_info)
  elseif def.create == "ask" then
    -- Only ask if explicitly triggered by user action (not during auto-scanning)
    if not no_create then
      -- Use centralized confirmation dialog
      utils.confirm_yesno("Create task for: " .. task_info.description .. "?", function(choice)
        if choice == 1 then
          M.create_task_for_tag(bufnr, lnum, task_info)
        else
          -- User declined, offer to add opt-out marker
          utils.confirm_yesno("Add [notrack] marker to prevent future prompts?", function(choice2)
            if choice2 == 1 then
              -- Add opt-out marker
              M.add_optout_marker(bufnr, lnum)
            end
          end)
        end
      end)
    end
  elseif def.create == "manual" then
    utils.notify(
      "Tag found: " .. task_info.description .. "\nUse :TaskforgeTag add to create task",
      vim.log.levels.INFO
    )
  end
end

-- Create a taskwarrior task for a tag
function M.create_task_for_tag(bufnr, lnum, task_info)
  local tasks = require("taskforge.tasks")

  tasks.create(task_info.description, task_info, function(uuid)
    if uuid then
      -- Link the UUID back to the comment
      local uuid_module = require("taskforge.tracker.uuid")
      uuid_module.link_uuid_to_comment(bufnr, lnum, uuid)
    end
  end)
end

-- Handle a removed UUID
function M.handle_removed_uuid(bufnr, lnum, uuid, tag_def)
  utils.debug_log("TAGS", "Tag with UUID removed", uuid)

  -- Find the tag definition
  local cfg = config.get().tags
  if not tag_def then
    -- Try to find tag_def from the task itself
    local tasks = require("taskforge.tasks")
    local task = tasks.get_task(uuid)

    if task and task.description then
      for tag, def in pairs(cfg.definitions or {}) do
        if task.description:match("^" .. tag) then
          tag_def = def
          break
        end

        -- Check alternative tags
        if def.alt then
          for _, alt in ipairs(def.alt) do
            if task.description:match("^" .. alt) then
              tag_def = def
              break
            end
          end
        end

        if tag_def then
          break
        end
      end
    end
  end

  -- Handle based on close action
  if tag_def and tag_def.close == "auto" then
    require("taskforge.tasks").done(uuid)
    utils.notify("Task automatically marked done (tag removed)", vim.log.levels.INFO)
  elseif tag_def and tag_def.close == "ask" then
    utils.confirm_yesno("Mark task as done? (Tag removed)", function(choice)
      if choice == 1 then
        require("taskforge.tasks").done(uuid)
        utils.notify("Task marked as done", vim.log.levels.INFO)
      end
    end)
  elseif tag_def and tag_def.close == "manual" then
    utils.notify("Tag removed. Use :Taskforge done " .. uuid .. " to mark task as done", vim.log.levels.WARN)
  end
end

-- Add an opt-out marker to a comment
function M.add_optout_marker(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]

  -- Add [notrack] marker to the comment
  local new_line
  local ft = vim.bo[bufnr].filetype
  local lang = require("taskforge.lang").get_for_buffer(bufnr)

  -- Use language module to add marker properly
  if lang.add_optout_marker then
    new_line = lang.add_optout_marker(line, ft)
  else
    -- Fallback implementation
    if line:match("%*/+%s*$") then
      -- Block comment, insert before closing */
      new_line = line:gsub("%*/+%s*$", " [notrack] */")
    else
      -- Just append
      new_line = line .. " [notrack]"
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
  utils.notify("Added [notrack] marker to prevent future prompts", vim.log.levels.INFO)
end

-- Handle task status change
function M.handle_task_status_change(uuid, new_status)
  local cfg = config.get()

  -- Check if we're tracking this task
  local task = core.get_task(uuid)
  if not task then
    return
  end

  if new_status == "completed" then
    -- Task was completed, remove or update the tag
    if vim.fn.filereadable(task.file) == 1 then
      -- Open the file
      local buf = vim.fn.bufadd(task.file)
      vim.fn.bufload(buf)

      -- Check the line
      if task.line and task.line <= vim.api.nvim_buf_line_count(buf) then
        local line = vim.api.nvim_buf_get_lines(buf, task.line - 1, task.line, false)[1]

        -- Check if UUID exists in line
        if line:match(core.constants.uuid_pattern) then
          -- Remove tag or mark as DONE based on config
          local remove_tag = cfg.tags and cfg.tags.remove_on_done

          if remove_tag then
            -- Remove the entire line or just the tag
            if cfg.tags.remove_line_on_done then
              vim.api.nvim_buf_set_lines(buf, task.line - 1, task.line, false, {})
            else
              -- Just remove the tag part
              local new_line = line:gsub("%s*[A-Z]+:%s*", ""):gsub("%s*%[task:[0-9a-f%-]+%]", "")
              vim.api.nvim_buf_set_lines(buf, task.line - 1, task.line, false, { new_line })
            end

            utils.debug_log("TAGS", "Removed tag from completed task", uuid)
          else
            -- Mark it as DONE instead
            local new_line = line:gsub("([A-Z]+):", "DONE:")
            vim.api.nvim_buf_set_lines(buf, task.line - 1, task.line, false, { new_line })

            utils.debug_log("TAGS", "Updated tag to DONE for completed task", uuid)
          end
        end
      end
    end
  end

  -- Update cache
  core.update_task_status(uuid, new_status)
end

-- Add a new tag at the cursor position
function M.add_at_cursor()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line = vim.api.nvim_get_current_line()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Check if cursor is in a comment
  local lang = require("taskforge.lang").get_for_buffer(bufnr)
  local context = lang.detect_comment_context(bufnr, lnum)
  local is_comment = context.is_comment

  if is_comment then
    -- Already a comment, check if it has a tag
    local cfg = config.get().tags
    local has_tag = false

    for tag, def in pairs(cfg.definitions or {}) do
      -- Check main and alternative tags
      local tags_to_check = { tag }
      if def.alt then
        vim.list_extend(tags_to_check, def.alt)
      end

      for _, tag_name in ipairs(tags_to_check) do
        if line:match(tag_name) then
          has_tag = true

          -- Found existing tag, process it directly
          local node = M._get_node_at_line(bufnr, lnum)
          if node then
            M.process_tag(bufnr, lnum, tag_name, def, node, false) -- false = allow task creation
          end

          break
        end
      end

      if has_tag then
        break
      end
    end

    if not has_tag then
      -- Comment without tag, ask for tag type
      M._add_tag_to_comment(bufnr, lnum, line)
    end
  else
    -- Not a comment, create a new comment with tag
    M._create_comment_with_tag(bufnr, lnum)
  end
end

-- Add a tag to an existing comment
function M._add_tag_to_comment(bufnr, lnum, line)
  local cfg = config.get().tags
  local tags = {}

  for tag, _ in pairs(cfg.definitions or {}) do
    table.insert(tags, tag)
  end

  vim.ui.select(tags, {
    prompt = "Select tag type for this comment:",
  }, function(tag)
    if tag then
      -- Add tag to the comment
      local ft = vim.bo[bufnr].filetype
      local lang = require("taskforge.lang").get_for_buffer(bufnr)

      -- Let language module add tag if it has a method for it
      local new_line
      if lang.add_tag_to_comment then
        new_line = lang.add_tag_to_comment(line, tag, ft)
      else
        -- Fallback method
        new_line = line:gsub('^(%s*[/#"%*]+%s*)', "%1" .. tag .. ": ")
      end

      vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

      -- Process the buffer to create the task
      local def = cfg.definitions[tag]
      local node = M._get_node_at_line(bufnr, lnum)

      if node and def then
        M.process_tag(bufnr, lnum, tag, def, node, false) -- false = allow task creation
      end
    end
  end)
end

-- Create a new comment with a tag
function M._create_comment_with_tag(bufnr, lnum)
  local cfg = config.get().tags
  local tags = {}

  for tag, _ in pairs(cfg.definitions or {}) do
    table.insert(tags, tag)
  end

  vim.ui.select(tags, {
    prompt = "Select tag type:",
  }, function(tag)
    if tag then
      -- Create the comment with tag
      local ft = vim.bo[bufnr].filetype
      local lang = require("taskforge.lang").get_for_buffer(bufnr)

      -- Get comment prefix for this language
      local comment_prefix
      if lang.get_comment_prefix then
        comment_prefix = lang.get_comment_prefix(ft)
      else
        -- Fallback prefixes
        if ft == "lua" or ft == "python" or ft == "bash" or ft == "sh" then
          comment_prefix = "# "
        elseif ft == "vim" then
          comment_prefix = '" '
        else
          comment_prefix = "// "
        end
      end

      -- Ask for description
      vim.ui.input({
        prompt = "Description:",
      }, function(desc)
        if desc then
          local new_line = comment_prefix .. tag .. ": " .. desc
          vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

          -- Process the tag
          local def = cfg.definitions[tag]
          local node = M._get_node_at_line(bufnr, lnum)

          if node and def then
            M.process_tag(bufnr, lnum, tag, def, node, false) -- false = allow task creation
          end
        end
      end)
    end
  end)
end

-- Get a treesitter node at a specific line
function M._get_node_at_line(bufnr, lnum)
  -- Try treesitter if available
  if vim.treesitter then
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if ok and parser then
      local tree = parser:parse()[1]
      if tree then
        local root = tree:root()
        if root then
          -- Get line text to determine length
          local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""

          -- Find a node at this line
          local node = root:named_descendant_for_range(lnum, 0, lnum, #line)

          -- Go up the tree until we find a comment node
          while node do
            if node:type() == "comment" or node:type() == "line_comment" or node:type() == "block_comment" then
              return node
            end
            node = node:parent()
          end
        end
      end
    end
  end

  return nil
end

-- Remove a tag at cursor position
function M.remove_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line = vim.api.nvim_get_current_line()

  -- Check if line has a UUID
  local uuid = line:match(core.constants.uuid_pattern)
  if uuid then
    -- Use centralized confirmation dialog
    utils.confirm_yesno("Remove tag and mark task as done?", function(choice)
      if choice == 1 then
        -- Mark task as done
        require("taskforge.tasks").done(uuid)

        -- Remove UUID from line
        local new_line = line:gsub("%s*%[task:[0-9a-f%-]+%]", "")
        vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

        utils.notify("Task marked as done and tag removed", vim.log.levels.INFO)
      end
    end)
  else
    -- No UUID, check if it's a tag line
    local has_tag = false
    local cfg = config.get().tags

    for tag, _ in pairs(cfg.definitions or {}) do
      if line:match(tag) then
        has_tag = true
        break
      end
    end

    if has_tag then
      -- Just remove the tag prefix
      local new_line = line:gsub('(%s*[/#"%*]+%s*)[A-Z]+:%s*', "%1")
      vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

      utils.notify("Tag removed", vim.log.levels.INFO)
    else
      utils.notify("No tag found at cursor position", vim.log.levels.WARN)
    end
  end
end

-- Add opt-out marker at cursor position
function M.add_optout_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

  -- Add the opt-out marker
  M.add_optout_marker(bufnr, lnum)

  -- Re-process the buffer so the comment won't be tracked
  local buffer = require("taskforge.tracker.buffer")
  buffer.process(bufnr)
end

-- Link current comment to an existing task
function M.link_to_task()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line = vim.api.nvim_get_current_line()

  -- Check if line already has UUID
  if line:match(core.constants.uuid_pattern) then
    utils.notify("Comment already linked to a task", vim.log.levels.WARN)
    return
  end

  -- Get available tasks
  local tasks = require("taskforge.tasks")
  local all_tasks = tasks.list()

  -- Format tasks for selection
  local items = {}
  for _, task in ipairs(all_tasks) do
    table.insert(items, {
      text = task.description,
      uuid = task.uuid,
    })
  end

  -- Let user select a task
  vim.ui.select(items, {
    prompt = "Select task to link:",
    format_item = function(item)
      return item.text
    end,
  }, function(selected)
    if selected then
      -- Link the UUID to the comment
      local uuid_module = require("taskforge.tracker.uuid")
      uuid_module.link_uuid_to_comment(bufnr, lnum, selected.uuid)
    end
  end)
end

return M

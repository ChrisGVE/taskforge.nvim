-- User command definitions and dispatch
-- Handles :Taskforge commands and keymaps

local M = {}
local utils = require("taskforge.utils")

function M.register()
  -- Create main user command
  vim.api.nvim_create_user_command("Taskforge", function(opts)
    local subcmd = opts.fargs[1]
    local args = { unpack(opts.fargs, 2) } -- Get all arguments after subcommand

    utils.debug_log("COMMANDS", "Running command", { cmd = subcmd, args = args })

    if subcmd == "dashboard" then
      M.cmd_dashboard()
    elseif subcmd == "config" then
      M.cmd_configure()
    elseif subcmd == "pick" then
      M.cmd_pick()
    elseif subcmd == "create" then
      M.cmd_create(args)
    elseif subcmd == "done" then
      M.cmd_done(args)
    elseif subcmd == "delete" then
      M.cmd_delete(args)
    elseif subcmd == "annotate" then
      M.cmd_annotate(args)
    elseif subcmd == "jump" then
      M.cmd_jump(args)
    elseif subcmd == "refresh" then
      M.cmd_refresh()
    elseif subcmd == "tag" then
      M.cmd_tag(args)
    elseif subcmd == "test" then
      M.cmd_test()
    else
      utils.notify("Unknown command: " .. subcmd, vim.log.levels.ERROR)
    end
  end, {
    nargs = "+",
    complete = function(arglead, cmdline, curpos)
      local subcmds = {
        "dashboard",
        "pick",
        "create",
        "done",
        "delete",
        "annotate",
        "jump",
        "refresh",
        "config",
        "tag",
        "test",
      }

      -- Check if we're completing a subcommand or an argument
      local args = vim.split(cmdline, "%s+")

      if #args <= 2 then -- Only command and possibly partial subcommand
        -- Filter subcommands based on partial input
        if arglead ~= "" then
          local matches = {}
          for _, cmd in ipairs(subcmds) do
            if cmd:find(arglead, 1, true) == 1 then
              table.insert(matches, cmd)
            end
          end
          return matches
        else
          return subcmds
        end
      else
        -- Completing arguments to a subcommand
        local subcmd = args[2]

        -- For now, only task UUIDs are completed
        if subcmd == "done" or subcmd == "delete" or subcmd == "annotate" or subcmd == "jump" then
          local tasks = require("taskforge.tasks").list()
          local matches = {}

          for _, task in ipairs(tasks) do
            if task.uuid:find(arglead, 1, true) == 1 then
              table.insert(matches, task.uuid)
            end
          end

          return matches
        elseif subcmd == "tag" then
          return { "add", "remove", "link" }
        end
      end

      return {}
    end,
  })

  -- Example keymaps (configurable)
  local cfg = require("taskforge.config").get().interface
  if cfg and cfg.keymaps then
    local keymaps = cfg.keymaps

    -- Task finder
    if keymaps.open then
      vim.keymap.set("n", keymaps.open, "<cmd>Taskforge pick<cr>", { desc = "Find tasks" })
    end

    -- Tag management
    vim.keymap.set("n", "<leader>ta", "<cmd>Taskforge tag add<cr>", { desc = "Add tag at cursor" })
    vim.keymap.set("n", "<leader>tr", "<cmd>Taskforge tag remove<cr>", { desc = "Remove tag at cursor" })
    vim.keymap.set("n", "<leader>tl", "<cmd>Taskforge tag link<cr>", { desc = "Link tag to task" })
  end
end

-- Command implementations
function M.cmd_dashboard()
  local interface = require("taskforge.interface")
  if interface.open_dashboard then
    interface.open_dashboard()
  end
end

function M.cmd_configure()
  require("taskforge.tasks").configure()
end

function M.cmd_pick()
  local picker = require("taskforge.picker")
  if picker.open_task_picker then
    picker.open_task_picker()
  else
    utils.notify("Task picker not available", vim.log.levels.ERROR)
  end
end

function M.cmd_create(args)
  if #args == 0 then
    -- Interactive mode
    vim.ui.input({
      prompt = "Task description: ",
    }, function(description)
      if description and description ~= "" then
        -- Ask for project
        local project = require("taskforge.project").current()
        require("taskforge.tasks").create(description, { project = project })
      end
    end)
  else
    -- From command line
    local description = table.concat(args, " ")
    local project = require("taskforge.project").current()
    require("taskforge.tasks").create(description, { project = project })
  end
end

function M.cmd_done(args)
  if #args == 0 then
    -- No UUID provided, try to get current task
    local bufnr = vim.api.nvim_get_current_buf()
    local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

    if M.buf_cache and M.buf_cache[bufnr] and M.buf_cache[bufnr][lnum] then
      local uuid = M.buf_cache[bufnr][lnum].uuid
      if uuid then
        require("taskforge.tasks").done(uuid)
      else
        utils.notify("No task found at cursor position", vim.log.levels.ERROR)
      end
    else
      -- Try to look for UUID in the current line
      local line = vim.api.nvim_get_current_line()
      local uuid = line:match("%[task:([0-9a-f%-]+)%]")
      if uuid then
        require("taskforge.tasks").done(uuid)
      else
        utils.notify("No task UUID provided", vim.log.levels.ERROR)
      end
    end
  else
    -- UUID provided as argument
    require("taskforge.tasks").done(args[1])
  end
end

function M.cmd_delete(args)
  if #args == 0 then
    utils.notify("No task UUID provided", vim.log.levels.ERROR)
  else
    require("taskforge.tasks").delete(args[1])
  end
end

function M.cmd_annotate(args)
  if #args < 2 then
    utils.notify("Usage: Taskforge annotate <uuid> <text>", vim.log.levels.ERROR)
  else
    local uuid = args[1]
    local text = table.concat({ unpack(args, 2) }, " ")
    require("taskforge.tasks").annotate(uuid, text)
  end
end

function M.cmd_jump(args)
  if #args == 0 then
    -- No UUID provided, try to get current task
    local tasks = require("taskforge.tasks").list()
    vim.ui.select(tasks, {
      prompt = "Select task to jump to:",
      format_item = function(task)
        return task.description .. " [" .. task.uuid .. "]"
      end,
    }, function(task)
      if task then
        require("taskforge.tasks").jump_to_task(task.uuid)
      end
    end)
  else
    -- UUID provided as argument
    require("taskforge.tasks").jump_to_task(args[1])
  end
end

function M.cmd_refresh()
  require("taskforge.tasks").refresh_cache()
  utils.notify("Task cache refreshed")
end

function M.cmd_tag(args)
  if #args == 0 then
    utils.notify("Usage: Taskforge tag <add|remove|link>", vim.log.levels.ERROR)
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
  else
    utils.notify("Unknown tag command: " .. subcmd, vim.log.levels.ERROR)
  end
end

function M.cmd_test()
  -- Test various functionalities for debugging
  utils.debug_log("COMMANDS", "Running test command")

  -- Test project detection
  local project = require("taskforge.project").current()
  utils.notify("Current project: " .. tostring(project))

  -- Test task listing
  local tasks = require("taskforge.tasks").list()
  utils.notify("Found " .. #tasks .. " tasks")

  -- More tests as needed...
end

return M

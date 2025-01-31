local commands = require("taskforge.commands")
local utils = require("taskforge.utils.utils")

local subcommands = {}

function subcommands.complete(arg, cmd_line)
  local matches = {}
  local lack_taskwarrior_tui = vim.fn.executable("taskwarrior-tui") ~= 1

  local words = vim.split(cmd_line, " ", { trimempty = true })
  if not vim.endswith(cmd_line, " ") then
    -- Last word is not fully typed, don't count it
    table.remove(words, #words)
  end

  if #words == 1 then
    for subcommand in pairs(commands) do
      if
        vim.startswith(subcommand, arg) and not vim.startswith(subcommand, "auto") and subcommand ~= "setup"
        or lack_taskwarrior_tui and subcommand ~= "taskwarrior_tui"
      then
        table.insert(matches, subcommand)
      end
    end
  end

  return matches
end

function subcommands.run(subcommand)
  local subcommand_func = commands[subcommand.fargs[1]]
  if not subcommand_func then
    utils.notify("No such subcommand: " .. subcommand.fargs[1], vim.log.levels.ERROR)
    return
  end
  subcommand_func(subcommand.bang)
end

return subcommands

-- lua/taskforge/tracker.lua
local M = {}
local config = require("taskforge.config")
local ns = vim.api.nvim_create_namespace("taskforge_tags")

function M.setup()
  M.buf_cache = {}
  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged" }, {
    callback = function()
      M.process_buffer(0)
    end,
  })
end

function M.process_buffer(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  M.clear_tags(bufnr)

  for lnum, line in ipairs(lines) do
    for tag, def in pairs(config.get().tags.definitions) do
      if line:match(def.pattern or tag) then
        M.handle_tag(bufnr, lnum - 1, line, tag, def)
      end
    end
  end
end

function M.handle_tag(bufnr, lnum, line, tag, def)
  -- Store tag metadata
  local task = {
    description = line:match(def.pattern .. "%s*(.+)"),
    project = require("taskforge.project").current(),
    tags = def.tags,
    due = def.due,
    priority = def.priority,
  }

  -- Create task based on configuration
  if def.create == "auto" then
    require("taskforge.tasks").create(task)
  elseif def.create == "ask" then
    vim.ui.confirm("Create task for: " .. line, function(yes)
      if yes then
        require("taskforge.tasks").create(task)
      end
    end)
  end

  -- Visual marker
  vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
    virt_text = { { tag, "Comment" } },
    virt_text_pos = "eol",
  })
end

return M

require("taskforge")


-- if not vim.fn.has('nvim-0.7.0') then
--   require('session_manager.utils').notify('Neovim 0.7+ is required for session manager plugin', vim.log.levels.ERROR)
--   return
-- end

local subcommands = require('taskforge.subcommands')
-- local taskforge = require('taskforge')

vim.api.nvim_create_user_command('TaskForge', subcommands.run, { nargs = 1, bang = true, complete = subcommands.complete, desc = 'Run Task Forge command' })

-- local taskforge_group = vim.api.nvim_create_augroup('TaskForge', {})
-- vim.api.nvim_create_autocmd({ 'VimEnter' }, {
--   group = taskforge_group,
--   nested = true,
--   callback = taskforge.autoload_session,
-- })
-- vim.api.nvim_create_autocmd({ 'VimLeavePre' }, {
--   group = taskforge_group,
--   callback = taskforge.autosave_session,
-- })
-- vim.api.nvim_create_autocmd({ 'StdinReadPre' }, {
--   group = taskforge_group,
--   callback = function() vim.g.started_with_stdin = true end,
-- })

-- This module contains everything for highlighting Hop.
local M = {}

-- Insert the highlights that Hop uses.
function M.insert_highlights()
  -- Highlight used for the mono-sequence keys (i.e. sequence of 1).
  vim.api.nvim_command('highlight default HopNextKey  guifg=#ff007c gui=bold ctermfg=198 cterm=bold')

  -- Highlight used for the first key in a sequence.
  vim.api.nvim_command('highlight default HopNextKey1 guifg=#00dfff gui=bold ctermfg=45 cterm=bold')

  -- Highlight used for the second and remaining keys in a sequence.
  vim.api.nvim_command('highlight default HopNextKey2 guifg=#2b8db3 ctermfg=33')

  -- Highlight used for the unmatched part of the buffer.
  vim.api.nvim_command('highlight default HopUnmatched guifg=#666666 ctermfg=242')
end

function M.create_autocmd()
  vim.api.nvim_command('augroup HopInitHighlight')
  vim.api.nvim_command('autocmd!')
  vim.api.nvim_command("autocmd ColorScheme * lua require'hop.highlight'.insert_highlights()")
  vim.api.nvim_command('augroup end')
end

return M

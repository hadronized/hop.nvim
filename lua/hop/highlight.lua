-- This module contains everything for highlighting Hop.
local M = {}

-- Insert the highlights that Hop uses.
function M.insert_highlights()
  -- Highlight used for the mono-sequence keys (i.e. sequence of 1).
  vim.api.nvim_set_hl(0, 'HopNextKey', { fg = '#ff007c', bold = true, ctermfg = 198, cterm = { bold = true } })

  -- Highlight used for the first key in a sequence.
  vim.api.nvim_set_hl(0, 'HopNextKey1', { fg = '#00dfff', bold = true, ctermfg = 45, cterm = { bold = true } })

  -- Highlight used for the second and remaining keys in a sequence.
  vim.api.nvim_set_hl(0, 'HopNextKey2', { fg = '#2b8db3', ctermfg = 33 })

  -- Highlight used for the unmatched part of the buffer.
  vim.api.nvim_set_hl(0, 'HopUnmatched', { fg = '#666666', sp = '#666666', ctermfg = 242 })

  -- Highlight used for the fake cursor visible when hopping.
  vim.api.nvim_set_hl(0, 'HopCursor', { link = 'Cursor' })

  -- Highlight used for preview pattern
  vim.api.nvim_set_hl(0, 'HopPreview', { link = 'IncSearch' })
end

function M.create_autocmd()
  vim.api.nvim_create_autocmd('ColorScheme', {

    group = vim.api.nvim_create_augroup('HopInitHighlight', {
      clear = true,
    }),

    callback = function()
      require('hop.highlight').insert_highlights()
    end,
  })
end

return M

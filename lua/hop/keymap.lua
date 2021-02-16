local defaults = require'hop.defaults'

local M = {}

-- Create the keymap based on the input keys and insert it in the input buffer via its handle.
--
-- This function creates the keymap allowing a user to:
--
-- - Jump to a target hint.
-- - Quit with q.
function M.create_jump_keymap(buf_handle, opts)
  local keys = opts and opts.keys or defaults.keys

  -- remap all the jump keys
  for i = 1, #keys do
    local key = keys:sub(i, i)
    vim.api.nvim_buf_set_keymap(buf_handle, '', key, "<cmd>lua require'hop'.refine_hints(0, '" .. key .. "')<cr>", { nowait = true })
  end

  vim.api.nvim_buf_set_keymap(buf_handle, '', '<esc>', "<cmd>lua require'hop'.quit(0)<cr>", {})
end

return M

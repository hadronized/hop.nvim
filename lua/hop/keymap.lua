local M = {}

-- Create the keymap based on the input keys and insert it in the input buffer via its handle.
--
-- This function creates the keymap allowing a user to:
--
-- - Jump to a target hint.
-- - Quit with q.
function M.create_jump_keymap(buf_handle, opts)
  local keys = opts.keys

  -- save the keymaps to be able to restore them later
  local prev_keymap = vim.api.nvim_buf_get_keymap(buf_handle, '')
  vim.api.nvim_buf_set_var(buf_handle, 'hop#prev_keymap', prev_keymap)
  local keymap = {}

  -- remap all the jump keys
  for i = 1, #keys do
    local key = keys:sub(i, i)
    keymap[#keymap + 1] = key
    vim.api.nvim_buf_set_keymap(buf_handle, '', key, "<cmd>lua require'hop'.refine_hints(0, '" .. key .. "')<cr>", { nowait = true })
  end

  vim.api.nvim_buf_set_keymap(buf_handle, '', '<esc>', "<cmd>lua require'hop'.quit(0)<cr>", {})
  keymap[#keymap + 1] = '<esc>'

  vim.api.nvim_buf_set_var(buf_handle, 'hop#keymap', keymap)
end

local function find_mapping(keymap, lhs)
  for _, m in pairs(keymap) do
    if m.lhs == lhs then
      return m
    end
  end

  return nil
end

function M.restore_keymap(buf_handle)
  local prev_keymap = vim.api.nvim_buf_get_var(buf_handle, 'hop#prev_keymap')
  local keymap = vim.api.nvim_buf_get_var(buf_handle, 'hop#keymap')

  for _, lhs in pairs(keymap) do
    local mapping = find_mapping(prev_keymap, lhs)

    if mapping ~= nil then
      vim.api.nvim_buf_set_keymap(buf_handle, '', lhs, mapping.rhs, { silent = mapping.silent == 1; noremap = mapping.noremap == 1; script = mapping.script == 1; expr = mapping.expr == 1 })
    else
      vim.api.nvim_buf_del_keymap(buf_handle, '', lhs)
    end
  end

  vim.api.nvim_buf_del_var(buf_handle, 'hop#keymap')
  vim.api.nvim_buf_del_var(buf_handle, 'hop#prev_keymap')
end

return M

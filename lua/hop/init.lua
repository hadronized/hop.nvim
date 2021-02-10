local defaults = require'hop.defaults'
local hint = require'hop.hint'
local keymap = require'hop.keymap'

local M = {}

-- Update the hint buffer.
local function update_hint_buffer(buf_handle, win_width, win_height, hints)
  local lines = hint.create_buffer_lines(win_width, win_height, hints)

  vim.api.nvim_buf_set_lines(buf_handle, 0, -1, true, lines)

  for line = 1, win_height do
    vim.api.nvim_buf_add_highlight(buf_handle, -1, 'EndOfBuffer', line - 1, 0, -1)

    for _, h in pairs(hints[line].hints) do
      local hint_len = #h.hint

      if hint_len == 1 then
        vim.api.nvim_buf_add_highlight(buf_handle, -1, 'HopNextKey', h.line - 1, h.col - 1, h.col)
      else
        vim.api.nvim_buf_add_highlight(buf_handle, -1, 'HopNextKey1', h.line - 1, h.col - 1, h.col)
        vim.api.nvim_buf_add_highlight(buf_handle, -1, 'HopNextKey2', h.line - 1, h.col, h.col + #h.hint - 1)
      end
    end
  end
end

function M.jump_words(opts)
  -- abort if we’re already in a hop buffer
  if vim.b['hop#marked'] then
    local teasing = nil
    if opts and opts.teasing ~= nil then
      teasing = opts.teasing
    else
      teasing = defaults.teasing
    end

    if teasing then
      vim.cmd('echohl Error|echo "eh, don’t open hop from within hop, that’s super dangerous!"')
    end

    return
  end

  local winblend = opts and opts.winblend or defaults.winblend

  local win_view = vim.fn.winsaveview()
  local win_info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  local cursor_line = win_view['lnum']
  local cursor_col = win_view['col']
  local win_top_line = win_view['topline'] - 1
  -- NOTE: due to an (unknown yet) bug in neovim, the sign_width is not correctly reported when shifting the window
  -- view inside a non-wrap window, so we can’t rely on this; for this reason, we have to implement a weird hack that
  -- is going to disable the signs while hop is running (I’m sorry); the state is restored after jump
  -- local left_col_offset = win_info.variables.context.number_width + win_info.variables.context.sign_width

  -- hack to get the left column offset
  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })
  local left_col_offset = vim.fn.wincol() - 1
  vim.fn.winrestview(win_view)

  local win_width = win_info.width - left_col_offset
  local win_real_height = vim.api.nvim_win_get_height(0)
  local win_height = win_info.botline - win_info.topline + 1
  local win_lines = vim.api.nvim_buf_get_lines(0, win_info.topline - 1, win_info.botline, false)

  local screenpos = vim.fn.screenpos(0, cursor_line, cursor_col)
  local cursor_pos = { cursor_line - win_info.topline + 1, cursor_col }

  -- in wrap, we do not pass the width of the window so that we get lines
  -- wrapping around correctly
  local buf_width = nil
  if not vim.wo.wrap then
    buf_width = win_width
  end

  local hints = hint.create_hints(
    hint.by_word_start,
    buf_width,
    win_height,
    cursor_pos,
    win_view.leftcol,
    win_lines,
    opts
  )

  -- create a new buffer to contain the hints and mark it as ours with b:hop#marked; this will allow us to know
  -- whether we try to call hop again from within such a buffer (and actually prevent it)
  local hint_buf_handle = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_var(hint_buf_handle, 'hop#marked', true)

  -- fill the hint buffer
  update_hint_buffer(hint_buf_handle, win_width, win_height, hints)

  local win_id = vim.api.nvim_open_win(hint_buf_handle, true, {
    relative = 'win',
    width = win_width,
    height = win_real_height,
    row = 0,
    col = left_col_offset,
    style = 'minimal'
  })
  vim.api.nvim_win_set_option(win_id, 'winblend', winblend)
  -- FIXME: the cursor line is outside of the screen for vertical splits with this code
  -- vim.api.nvim_win_set_cursor(win_id, { cursor_line, cursor_col })

  -- buffer-local variables so that we can access them later
  vim.api.nvim_buf_set_var(hint_buf_handle, 'src_win_id', vim.api.nvim_get_current_win())
  vim.api.nvim_buf_set_var(hint_buf_handle, 'win_top_line', win_top_line)
  vim.api.nvim_buf_set_var(hint_buf_handle, 'win_width', win_width)
  vim.api.nvim_buf_set_var(hint_buf_handle, 'win_height', win_height)
  vim.api.nvim_buf_set_var(hint_buf_handle, 'hints', hints)

  -- keybindings
  keymap.create_jump_keymap(hint_buf_handle, opts)
end

-- Refine hints of the current buffer.
--
-- If the key doesn’t end up refining anything, TODO.
function M.refine_hints(buf_handle, key)
  local h, hints, update_count = hint.reduce_hints_lines(vim.b.hints, key)

  if h == nil then
    if update_count == 0 then
      -- TODO: vim.fn.echo_hl doesn’t seem to be implemented right now :(
      vim.cmd('echohl Error|echo "no remaining sequence starts with ' .. key .. '"')
      return
    end

    vim.api.nvim_buf_set_var(buf_handle, 'hints', hints)
    update_hint_buffer(buf_handle, vim.b.win_width, vim.b.win_height, hints)
  else
    local win_top_line = vim.b.win_top_line

    vim.api.nvim_buf_delete(buf_handle, {})

    -- prior to jump, register the current position into the jump list
    vim.cmd("normal m'")

    -- JUMP!
    vim.api.nvim_win_set_cursor(buf_handle, { win_top_line + h.line, h.real_col - 1})
  end
end

return M

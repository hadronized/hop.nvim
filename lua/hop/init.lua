local defaults = require'hop.defaults'
local hint = require'hop.hint'

local M = {}

-- Allows to override global options with user local overrides.
local function get_command_opts(local_opts)
  -- In case, local opts are defined, chain opts lookup: [user_local] -> [user_global] -> [default]
  return local_opts and setmetatable(local_opts, {__index = M.opts}) or M.opts
end

-- Display error messages.
local function eprintln(msg, teasing)
  if teasing then
    vim.api.nvim_echo({{msg, 'Error'}}, true, {})
  end
end

-- A hack to prevent #57 by deleting twice the namespace (it’s super weird).
local function clear_namespace(buf_handle, hl_ns)
  vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, 0, -1)
end

-- Grey everything out to prepare the Hop session.
--
-- - hl_ns is the highlight namespace.
-- - top_line is the top line in the buffer to start highlighting at
-- - bottom_line is the bottom line in the buffer to stop highlighting at
local function grey_things_out(buf_handle, hl_ns, top_line, bottom_line, direction_mode)
  clear_namespace(buf_handle, hl_ns)

  if direction_mode ~= nil then
    if direction_mode.direction == hint.HintDirection.AFTER_CURSOR then
      vim.api.nvim_buf_add_highlight(buf_handle, hl_ns, 'HopUnmatched', top_line, direction_mode.cursor_col, -1)
      for line_i = top_line + 1, bottom_line do
        vim.api.nvim_buf_add_highlight(buf_handle, hl_ns, 'HopUnmatched', line_i, 0, -1)
      end
    elseif direction_mode.direction == hint.HintDirection.BEFORE_CURSOR then
      for line_i = top_line, bottom_line - 1 do
        vim.api.nvim_buf_add_highlight(buf_handle, hl_ns, 'HopUnmatched', line_i, 0, -1)
      end
      vim.api.nvim_buf_add_highlight(buf_handle, hl_ns, 'HopUnmatched', bottom_line, 0, direction_mode.cursor_col)
    end
  else
    for line_i = top_line, bottom_line do
      vim.api.nvim_buf_add_highlight(buf_handle, hl_ns, 'HopUnmatched', line_i, 0, -1)
    end
  end
end

-- Cleanup Hop highlights and unmark the buffer.
local function unhl_and_unmark(buf_handle, hl_ns)
  clear_namespace(buf_handle, hl_ns)
  vim.api.nvim_buf_del_var(buf_handle, 'hop#marked')
end

-- Hint the whole visible part of the buffer.
--
-- The 'hint_mode' argument is the mode to use to hint the buffer.
local function hint_with(hint_mode, opts)
  -- first, we ensure we’re not already hopping around; if not, we mark the current buffer (this mark will be removed
  -- when a jump is performed or if the user stops hopping)
  -- abort if we’re already hopping
  if vim.b['hop#marked'] then
    eprintln('eh, don’t open hop from within hop, that’s super dangerous!', opts.teasing)
    return
  end

  vim.api.nvim_buf_set_var(0, 'hop#marked', true)

  -- get a bunch of information about the window and the cursor
  local win_info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  local win_view = vim.fn.winsaveview()
  local top_line = win_info.topline - 1
  local bot_line = win_info.botline - 1
  local cursor_pos = vim.api.nvim_win_get_cursor(0)

  -- adjust the visible part of the buffer to hint based on the direction
  local direction = opts.direction
  local direction_mode = nil
  if direction == hint.HintDirection.BEFORE_CURSOR then
    bot_line = cursor_pos[1] - 1
    direction_mode = { cursor_col = cursor_pos[2], direction = direction }
  elseif direction == hint.HintDirection.AFTER_CURSOR then
    top_line = cursor_pos[1] - 1
    direction_mode = { cursor_col = cursor_pos[2], direction = direction }
  end

  -- NOTE: due to an (unknown yet) bug in neovim, the sign_width is not correctly reported when shifting the window
  -- view inside a non-wrap window, so we can’t rely on this; for this reason, we have to implement a weird hack that
  -- is going to disable the signs while hop is running (I’m sorry); the state is restored after jump
  -- local left_col_offset = win_info.variables.context.number_width + win_info.variables.context.sign_width
  local win_width = nil

  -- hack to get the left column offset in nowrap
  if not vim.wo.wrap then
    vim.api.nvim_win_set_cursor(0, { cursor_pos[1], 0 })
    local left_col_offset = vim.fn.wincol() - 1
    vim.fn.winrestview(win_view)
    win_width = win_info.width - left_col_offset
  end

  -- create the highlight group and grey everything out; the highlight group will allow us to clean everything at once
  -- when hop quits
  local hl_ns = vim.api.nvim_create_namespace('')
  grey_things_out(0, hl_ns, top_line, bot_line, direction_mode)

  -- get the buffer lines and create hints; hint_counts allows us to display some error diagnostics to the user, if any,
  -- or even perform direct jump in the case of a single match
  local win_lines = vim.api.nvim_buf_get_lines(0, top_line, bot_line + 1, false)
  local hints, hint_counts = hint.create_hints(
    hint_mode,
    win_width,
    cursor_pos,
    win_view.leftcol,
    top_line,
    win_lines,
    direction,
    opts
  )

  local h = nil
  if hint_counts == 0 then
    eprintln(' -> there’s no such thing we can see…', opts.teasing)
    unhl_and_unmark(0, hl_ns)
    return
  elseif opts.jump_on_sole_occurrence and hint_counts == 1 then
    -- search the hint and jump to it
    for _, line_hints in pairs(hints) do
      if #line_hints.hints == 1 then
        h = line_hints.hints[1]
        unhl_and_unmark(0, hl_ns)
        vim.api.nvim_win_set_cursor(0, { h.line + 1, h.col - 1})
        break
      end
    end

    return
  end

  vim.api.nvim_buf_set_var(0, 'hop#hint_state', {
    hints = hints;
    hl_ns = hl_ns;
    top_line = top_line;
    bot_line = bot_line
  })

  hint.set_hint_extmarks(hl_ns, hints)
  vim.cmd('redraw')

  while h == nil do
    local ok, key = pcall(vim.fn.getchar)
    if not ok then
      M.quit(0)
      break
    end
    -- :h getchar(): "If the result of expr is a single character, it returns a
    -- number. Use nr2char() to convert it to a String."
    --
    -- Note of caution: Even though the result of `getchar()` might be a single
    -- character, that character might still be multiple bytes.
    if type(key) == 'number' then
      local key_str = vim.fn.nr2char(key)
      if opts.keys:find(key_str, 1, true) then
        -- If this is a key used in hop (via opts.keys), deal with it in hop
        h = M.refine_hints(0, key_str, opts.teasing, direction_mode)
        vim.cmd('redraw')
      else
        -- If it's not, quit hop and use the key like normal instead
        M.quit(0)
        -- Pass the key captured via getchar() through to nvim, to be handled
        -- normally (including mappings)
        vim.api.nvim_feedkeys(key_str, '', true)
        break
      end
    end
  end
end

-- Refine hints in the given buffer.
--
-- Refining hints allows to advance the state machine by one step. If a terminal step is reached, this function jumps to
-- the location. Otherwise, it stores the new state machine.
function M.refine_hints(buf_handle, key, teasing, direction_mode)
  local hint_state = vim.api.nvim_buf_get_var(buf_handle, 'hop#hint_state')
  local h, hints, update_count = hint.reduce_hints_lines(hint_state.hints, key)

  if h == nil then
    if update_count == 0 then
      eprintln('no remaining sequence starts with ' .. key, teasing)
      return
    end

    hint_state.hints = hints
    vim.api.nvim_buf_set_var(buf_handle, 'hop#hint_state', hint_state)

    grey_things_out(buf_handle, hint_state.hl_ns, hint_state.top_line, hint_state.bot_line, direction_mode)
    hint.set_hint_extmarks(hint_state.hl_ns, hints)
    vim.cmd('redraw')
  else
    M.quit(buf_handle)

    -- prior to jump, register the current position into the jump list
    vim.cmd("normal! m'")

    -- JUMP!
    vim.api.nvim_win_set_cursor(0, { h.line + 1, h.col - 1})
    return h
  end
end

-- Quit Hop and delete its resources.
--
-- This works only if the current buffer is Hop one.
function M.quit(buf_handle)
  local hint_state = vim.api.nvim_buf_get_var(buf_handle, 'hop#hint_state')
  unhl_and_unmark(buf_handle, hint_state.hl_ns)
end

function M.hint_words(opts)
  hint_with(hint.by_word_start, get_command_opts(opts))
end

function M.hint_patterns(opts)
  opts = get_command_opts(opts)

  vim.fn.inputsave()
  local ok, pat = pcall(vim.fn.input, 'Search: ')
  vim.fn.inputrestore()

  if not ok then return end

  if #pat == 0 then
    eprintln('-> empty pattern', opts.teasing)
    return
  end

  hint_with(hint.by_case_searching(pat, false, opts), opts)
end

function M.hint_char1(opts)
  opts = get_command_opts(opts)
  local ok, c = pcall(vim.fn.getchar)
  if not ok then return end
  hint_with(hint.by_case_searching(vim.fn.nr2char(c), true, opts), opts)
end

function M.hint_char2(opts)
  opts = get_command_opts(opts)
  local ok, a = pcall(vim.fn.getchar)
  if not ok then return end
  local ok2, b = pcall(vim.fn.getchar)
  if not ok2 then return end
  local pat = vim.fn.nr2char(a) .. vim.fn.nr2char(b)
  hint_with(hint.by_case_searching(pat, true, opts), opts)
end

function M.hint_lines(opts)
  hint_with(hint.by_line_start, get_command_opts(opts))
end

-- Setup user settings.
M.opts = defaults
function M.setup(opts)
  -- Look up keys in user-defined table with fallback to defaults.
  M.opts = setmetatable(opts or {}, {__index = defaults})

  -- Insert the highlights and register the autocommand if asked to.
  local highlight = require'hop.highlight'
  highlight.insert_highlights()

  if M.opts.create_hl_autocmd then
    highlight.create_autocmd()
  end
end

return M

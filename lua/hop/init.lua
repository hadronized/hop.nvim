local defaults = require'hop.defaults'
local hint = require'hop.hint'

local M = {}

M.opts = defaults

-- Setup user settings.
function M.setup(opts)
  -- Look up keys in user-defined table with fallback to defaults.
  M.opts = setmetatable(opts, {__index = defaults})
end

-- Allows to override global options with user local overrides.
local function get_command_opts(local_opts)
  -- In case, local opts are defined, chain opts lookup: [user_local] -> [user_global] -> [default]
  return local_opts and setmetatable(local_opts, {__index = M.opts}) or M.opts
end

-- Display error messages.
local function eprintln(opts, msg)
  if opts.teasing then
    vim.cmd(string.format('echohl Error|echo "%s"', msg))
  end
end

-- Grey everything out to prepare the Hop session.
--
-- - hl_ns is the highlight namespace.
-- - top_line is the top line in the buffer to start highlighting at
-- - bottom_line is the bottom line in the buffer to stop highlighting at
local function grey_things_out(buf_handle, hl_ns, top_line, bottom_line)
  for line_i = top_line, bottom_line do
    vim.api.nvim_buf_add_highlight(buf_handle, hl_ns, 'HopUnmatched', line_i, 0, -1)
  end
end

-- Cleanup Hop highlights and unmark the buffer.
local function unhl_and_unmark(buf_handle, hl_ns, top_line, bot_line)
  vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, top_line, bot_line)
  vim.api.nvim_buf_del_var(buf_handle, 'hop#marked')
end

local function hint_with(hint_mode, opts)
  -- first, we ensure we’re not already hopping around; if not, we mark the current buffer (this mark will be removed
  -- when a jump is performed or if the user stops hopping)
  -- abort if we’re already hopping
  if vim.b['hop#marked'] then
    eprintln(opts, 'eh, don’t open hop from within hop, that’s super dangerous!')
    return
  end

  vim.api.nvim_buf_set_var(0, 'hop#marked', true)

  -- get a bunch of information about the window and the cursor
  local win_info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  local win_view = vim.fn.winsaveview()
  local top_line = win_info.topline - 1
  local bot_line = win_info.botline - 1
  local cursor_pos = vim.api.nvim_win_get_cursor(0)

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
  grey_things_out(0, hl_ns, top_line, bot_line)

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
    opts
  )

  local h
  if hint_counts == 0 then
    eprintln(opts, ' -> there’s no such thing we can see…')
    unhl_and_unmark(0, hl_ns, top_line, bot_line)
    return
  elseif opts.jump_on_sole_occurrence and hint_counts == 1 then
    -- search the hint and jump to it
    for _, line_hints in pairs(hints) do
      if #line_hints.hints == 1 then
        h = line_hints.hints[1]
        unhl_and_unmark(0, hl_ns, top_line, bot_line)
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

  while h == nil do
    local key = vim.fn.getchar()
    if type(key) == 'number' then key = vim.fn.nr2char(key) end
    if #key == 1 and string.find(opts.keys, key, 1, true) then
      h = M.refine_hints(0, key)
    else
      M.quit(0)
      vim.api.nvim_feedkeys(key, '', true)
      break
    end
  end
end

-- Refine hints in the given buffer.
--
-- Refining hints allows to advance the state machine by one step. If a terminal step is reached, this function jumps to
-- the location. Otherwise, it stores the new state machine.
function M.refine_hints(buf_handle, key)
  local hint_state = vim.api.nvim_buf_get_var(buf_handle, 'hop#hint_state')
  local h, hints, update_count = hint.reduce_hints_lines(hint_state.hints, key)

  if h == nil then
    if update_count == 0 then
      -- TODO: vim.fn.echo_hl doesn’t seem to be implemented right now :(
      vim.cmd('echohl Error|echo "no remaining sequence starts with ' .. key .. '"')
      return
    end

    hint_state.hints = hints
    vim.api.nvim_buf_set_var(buf_handle, 'hop#hint_state', hint_state)

    vim.api.nvim_buf_clear_namespace(buf_handle, hint_state.hl_ns, hint_state.top_line, hint_state.bot_line)
    grey_things_out(buf_handle, hint_state.hl_ns, hint_state.top_line, hint_state.bot_line)
    hint.set_hint_extmarks(hint_state.hl_ns, hints)
  else
    M.quit(buf_handle)

    -- prior to jump, register the current position into the jump list
    vim.cmd("normal m'")

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
  unhl_and_unmark(buf_handle, hint_state.hl_ns, hint_state.top_line, hint_state.bot_line + 1)
end

function M.hint_words(opts)
  hint_with(hint.by_word_start, get_command_opts(opts))
end

function M.hint_words(opts)
  hint_with(hint.by_word_start, get_command_opts(opts))
end

function M.hint_patterns(opts)
  opts = get_command_opts(opts)

  vim.fn.inputsave()
  local pat = vim.fn.input('Search: ')
  vim.fn.inputrestore()

  if #pat == 0 then
    eprintln(opts, '-> empty pattern')
    return
  end

  hint_with(hint.by_searching(pat), opts)
end

function M.hint_char1(opts)
  local c = vim.fn.nr2char(vim.fn.getchar())
  hint_with(hint.by_searching(c, true), get_command_opts(opts))
end

function M.hint_char2(opts)
  local a = vim.fn.nr2char(vim.fn.getchar())
  local b = vim.fn.nr2char(vim.fn.getchar())
  hint_with(hint.by_searching(a .. b, true), get_command_opts(opts))
end

function M.hint_lines(opts)
  hint_with(hint.by_line_start, get_command_opts(opts))
end

-- Insert the highlights and register the autocommand.
local highlight = require'hop.highlight'
highlight.insert_highlights()
highlight.create_autocmd()

return M

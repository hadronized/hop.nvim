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
-- - hint_states in which the top_line in the buffer to start highlighting
--   at and the bot_line is the bottom line in the buffer to stop highlighting at
local function grey_things_out(hl_ns, hint_states)
  for _, hs in ipairs(hint_states) do
    clear_namespace(hs.handle.b, hl_ns)

    if hs.dir_mode ~= nil then
      if hs.dir_mode.direction == hint.HintDirection.AFTER_CURSOR then
        vim.api.nvim_buf_add_highlight(hs.handle.b, hl_ns, 'HopUnmatched', hs.top_line, hs.dir_mode.cursor_col, -1)
        for line_i = hs.top_line + 1, hs.bot_line do
          vim.api.nvim_buf_add_highlight(hs.handle.b, hl_ns, 'HopUnmatched', line_i, 0, -1)
        end
      elseif hs.dir_mode.direction == hint.HintDirection.BEFORE_CURSOR then
        for line_i = hs.top_line, hs.bot_line - 1 do
          vim.api.nvim_buf_add_highlight(hs.handle.b, hl_ns, 'HopUnmatched', line_i, 0, -1)
        end
        vim.api.nvim_buf_add_highlight(hs.handle.b, hl_ns, 'HopUnmatched', hs.bot_line, 0, hs.dir_mode.cursor_col)
      end
    else
      for line_i = hs.top_line, hs.bot_line do
        vim.api.nvim_buf_add_highlight(hs.handle.b, hl_ns, 'HopUnmatched', line_i, 0, -1)
      end
    end
  end
end

-- Create all hint state for all multi-windows.
-- Specification for `hint_states`:
-- {
--   {
--      handle = { w = <win-handle>, b = <buf-handle> },
--      cursor_pos = { },
--      top_line = 0,
--      bot_line = 0,
--      dir_mode = { },
--      col_offset = 0,
--      lnums = { },
--      lines = { },
--   },
--   ...
-- }
local function create_hint_states(opts)
  local hss = { } -- hint_states

  -- Current window as first item
  local cur_hwin = vim.api.nvim_get_current_win()
  local cur_hbuf = vim.api.nvim_win_get_buf(cur_hwin)
  hss[#hss + 1] = {
    handle = { w = cur_hwin, b = cur_hbuf },
    cursor_pos = vim.api.nvim_win_get_cursor(cur_hwin),
  }

  -- Other windows of current tabpage
  if opts.multi_windows then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local b = vim.api.nvim_win_get_buf(w)

      -- Remove duplicated buffers
      if w ~= cur_hwin and b ~= cur_hbuf then
        local h = nil
        for k in ipairs(hss) do
          if b == hss[k].handle.b then
            h = k
            break
          end
        end

        -- Use the window with larger area
        if h ~= nil then
          if vim.api.nvim_win_get_width(w) * vim.api.nvim_win_get_height(w) >
             vim.api.nvim_win_get_width(hss[h].handle.w) * vim.api.nvim_win_get_height(hss[h].handle.w)
          then
            hss[h].handle.w = w
          end
        else
          hss[#hss + 1] = {
            handle = { w = w, b = b },
            cursor_pos = vim.api.nvim_win_get_cursor(w),
          }
        end
      end
    end
  end

  return hss
end

-- Create hint lines from each windows to complete `hint_states` data
local function create_hint_lines(hs, opts)
  -- get a bunch of information about the window and the cursor
  local hwin = hs.handle.w
  local win_info = vim.fn.getwininfo(hwin)[1]
  local top_line = win_info.topline - 1
  local bot_line = win_info.botline - 1
  local cursor_pos = hs.cursor_pos

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
  hs.top_line = top_line
  hs.bot_line = bot_line
  hs.dir_mode = direction_mode

  -- NOTE: due to an (unknown yet) bug in neovim, the sign_width is not correctly reported when shifting the window
  -- view inside a non-wrap window, so we can’t rely on this; for this reason, we have to implement a weird hack that
  -- is going to disable the signs while hop is running (I’m sorry); the state is restored after jump
  -- local left_col_offset = win_info.variables.context.number_width + win_info.variables.context.sign_width
  -- hack to get the left column offset in nowrap
  local win_width = nil
  local win_leftcol = 0
  if not vim.wo.wrap then
    vim.api.nvim_set_current_win(hwin)
    vim.api.nvim_win_set_cursor(hwin, cursor_pos)
    local win_view = vim.fn.winsaveview()
    vim.api.nvim_win_set_cursor(hwin, { cursor_pos[1], 0 })
    local left_col_offset = vim.fn.wincol() - 1
    vim.fn.winrestview(win_view)

    win_width = win_info.width - left_col_offset
    win_leftcol = win_view.leftcol
  end
  hs.col_offset = win_leftcol

  -- get the buffer lines
  hs.lnums = {}
  hs.lines = {}
  local lnr = top_line + 1
  while lnr <= bot_line + 1 do
      table.insert(hs.lnums, lnr)
      local fold_end = vim.fn.foldclosedend(lnr)
      if fold_end == -1 then
        -- save line number and sliced line text to hint
        table.insert(hs.lines, vim.fn.getline(lnr):sub(win_leftcol + 1, win_width))
        lnr = lnr + 1
      else
        -- skip fold lines
        table.insert(hs.lines, '')
        lnr = fold_end + 1
      end
  end
end

local function hint_with(hint_mode, opts)
  local hl_ns = vim.api.nvim_create_namespace('')
  local hint_states = create_hint_states(opts)
  for _, hs in ipairs(hint_states) do
    create_hint_lines(hs, opts)
  end
  vim.api.nvim_set_current_win(hint_states[1].handle.w)

  -- Create call hints for all windows from hint_states
  local hints = hint.create_hints(hint_mode, hint_states, opts)

  if #hints == 0 then
    eprintln(' -> there’s no such thing we can see…', opts.teasing)
    return
  elseif opts.jump_on_sole_occurrence and #hints == 1 and #hints[1].hints == 1 then
    -- search the hint and jump to it
    local line_hints = hints[1]
    local h = line_hints.hints[1]
    vim.api.nvim_set_current_win(line_hints.handle.w)
    vim.api.nvim_win_set_cursor(line_hints.handle.w, { h.line + 1, h.col - 1})
    return
  end

  -- create the highlight group and grey everything out; the highlight group will allow us to clean everything at once
  -- when hop quits
  grey_things_out(hl_ns, hint_states)
  hint.set_hint_extmarks(hl_ns, hints)
  vim.cmd('redraw')

  -- jump to hints
  local h = nil
  while h == nil do
    local ok, key = pcall(vim.fn.getchar)
    if not ok then
      M.quit(hl_ns, hint_states)
      break
    end
    local not_special_key = true
    -- :h getchar(): "If the result of expr is a single character, it returns a
    -- number. Use nr2char() to convert it to a String." Also the result is a
    -- special key if it's a string and its first byte is 128.
    --
    -- Note of caution: Even though the result of `getchar()` might be a single
    -- character, that character might still be multiple bytes.
    if type(key) == 'number' then
      key = vim.fn.nr2char(key)
    elseif key:byte() == 128 then
      not_special_key = false
    end

    if not_special_key and opts.keys:find(key, 1, true) then
      -- If this is a key used in hop (via opts.keys), deal with it in hop
      h, hints = M.refine_hints(key, opts.teasing, hl_ns, hint_states, hints)
      vim.cmd('redraw')
    else
      -- If it's not, quit hop
      M.quit(hl_ns, hint_states)

      -- If the key captured via getchar() is not the quit_key, pass it through
      -- to nvim to be handled normally (including mappings)
      if key ~= vim.api.nvim_replace_termcodes(opts.quit_key, true, false, true) then
        vim.api.nvim_feedkeys(key, '', true)
      end
      break
    end
  end
end

-- Refine hints in the given buffer.
--
-- Refining hints allows to advance the state machine by one step. If a terminal step is reached, this function jumps to
-- the location. Otherwise, it stores the new state machine.
function M.refine_hints(key, teasing, hl_ns, hint_states, hints)
  local h, update_hints, update_count = hint.reduce_hints_lines(hints, key)

  if h == nil then
    if update_count == 0 then
      eprintln('no remaining sequence starts with ' .. key, teasing)
      update_hints = hints
    else
      grey_things_out(hl_ns, hint_states)
      hint.set_hint_extmarks(hl_ns, update_hints)
      vim.cmd('redraw')
    end
  else
    M.quit(hl_ns, hint_states)

    -- prior to jump, register the current position into the jump list
    vim.cmd("normal! m'")

    -- JUMP!
    vim.api.nvim_set_current_win(h.handle.w)
    vim.api.nvim_win_set_cursor(h.handle.w, { h.hints[1].line + 1, h.hints[1].col - 1})
  end

  return h, update_hints
end

-- Quit Hop and delete its resources.
function M.quit(hl_ns, hint_states)
  for _, hs in ipairs(hint_states) do
    clear_namespace(hs.handle.b, hl_ns)
  end
end

function M.hint_words(opts)
  hint_with(hint.by_word_start, get_command_opts(opts))
end

function M.hint_patterns(opts, pattern)
  opts = get_command_opts(opts)

  -- The pattern to search is either retrieved from the (optional) argument
  -- or directly from user input.
  if pattern then
    pat = pattern
  else
    vim.fn.inputsave()
    ok, pat = pcall(vim.fn.input, 'Search: ')
    vim.fn.inputrestore()
    if not ok then return end
  end

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

function M.hint_lines_skip_whitespace(opts)
  hint_with(hint.by_line_start_skip_whitespace(), get_command_opts(opts))
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

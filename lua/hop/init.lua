local defaults = require'hop.defaults'
local hint = require'hop.hint'
local constants = require'hop.constants'

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

-- Return the character index of col position in line
-- col index is 1-based in cell, char index returned is 0-based
local function str_col2char(line, col)
  if col <= 0 then
    return 0
  end

  local lw = vim.api.nvim_strwidth(line)
  local lc = vim.fn.strchars(line)
  -- No multi-byte character
  if lw == lc then
    return col
  end
  -- Line is shorter than col, all line should include
  if lw <= col then
    return lc
  end

  local lst
  if lc >= col then
    -- Line is very long
    lst = vim.fn.split(vim.fn.strcharpart(line, 0, col), '\\zs')
  else
    lst = vim.fn.split(line, '\\zs')
  end
  local i = 0
  local w = 0
  repeat
    i = i + 1
    w = w + vim.api.nvim_strwidth(lst[i])
  until (w >= col)
  return i
end

-- A hack to prevent #57 by deleting twice the namespace (it’s super weird).
local function clear_namespace(buf_handle, hl_ns)
  if vim.api.nvim_buf_is_valid(buf_handle) then
    vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, 0, -1)
  end
end

-- Highlight everything marked from pat_mode
-- - pat_mode if provided, highlight the pattern
local function highlight_things_out(hl_ns, hint_states, pat_mode)
  for _, hh in ipairs(hint_states) do
    local hbuf = hh.hbuf
    if not vim.api.nvim_buf_is_valid(hbuf) then
      goto __NEXT_HH
    end

    for _, hs in ipairs(hh) do
      -- Collect text list need to highlight
      local hl_lst = {}
      if hs.dir_mode ~= nil then
        if hs.dir_mode.direction == constants.HintDirection.AFTER_CURSOR then
          -- Hightlight lines after cursor
          vim.list_extend(hl_lst, hint.mark_hints_line(pat_mode, hs.lnums[1], hs.lines[1], hs.lcols[1], hs.dir_mode))
          for k = 2, #hs.lnums do
            vim.list_extend(hl_lst, hint.mark_hints_line(pat_mode, hs.lnums[k], hs.lines[k], hs.lcols[k], nil))
          end
        elseif hs.dir_mode.direction == constants.HintDirection.BEFORE_CURSOR then
          -- Hightlight lines before cursor
          for k = 1, #hs.lnums - 1 do
            vim.list_extend(hl_lst, hint.mark_hints_line(pat_mode, hs.lnums[k], hs.lines[k], hs.lcols[k], nil))
          end
          vim.list_extend(hl_lst, hint.mark_hints_line(pat_mode, hs.lnums[#hs.lnums], hs.lines[#hs.lnums], hs.lcols[#hs.lnums], hs.dir_mode))
        end
      else
        -- Hightlight all lines
        for k = 1, #hs.lnums do
          vim.list_extend(hl_lst, hint.mark_hints_line(pat_mode, hs.lnums[k], hs.lines[k], hs.lcols[k], hs.dir_mode))
        end
      end

      -- Highlight all matched text
      for _, h in ipairs(hl_lst) do
        vim.api.nvim_buf_add_highlight(hbuf, hl_ns, 'HopPreview', h.line, h.col - 1, h.col_end - 1)
      end
    end

    ::__NEXT_HH::
  end
end

-- Grey everything out to prepare the Hop session.
--
-- - hl_ns is the highlight namespace.
-- - hint_states in which the lnums in the buffer need to be highlighted
local function grey_things_out(hl_ns, hint_states)
  for _, hh in ipairs(hint_states) do
    local hbuf = hh.hbuf
    if not vim.api.nvim_buf_is_valid(hbuf) then
      goto __NEXT_HH
    end

    clear_namespace(hbuf, hl_ns)
    for _, hs in ipairs(hh) do
      -- Highlight unmatched lines
      if hs.dir_mode ~= nil then
        if hs.dir_mode.direction == constants.HintDirection.AFTER_CURSOR then
          -- Hightlight lines after cursor
          vim.api.nvim_buf_add_highlight(hbuf, hl_ns, 'HopUnmatched', hs.lnums[1], hs.dir_mode.cursor_col, -1)
          for k = 2, #hs.lnums do
            vim.api.nvim_buf_add_highlight(hbuf, hl_ns, 'HopUnmatched', hs.lnums[k], 0, -1)
          end
        elseif hs.dir_mode.direction == constants.HintDirection.BEFORE_CURSOR then
          -- Hightlight lines before cursor
          for k = 1, #hs.lnums - 1 do
            vim.api.nvim_buf_add_highlight(hbuf, hl_ns, 'HopUnmatched', hs.lnums[k], 0, -1)
          end
          vim.api.nvim_buf_add_highlight(hbuf, hl_ns, 'HopUnmatched', hs.lnums[#hs.lnums], 0, hs.dir_mode.cursor_col)
        end
      else
        -- Hightlight all lines
        for _, lnr in ipairs(hs.lnums) do
          vim.api.nvim_buf_add_highlight(hbuf, hl_ns, 'HopUnmatched', lnr, 0, -1)
        end
      end
    end

    ::__NEXT_HH::
  end
end

-- Create all hint state for all multi-windows.
-- Specification for `hint_states`:
--{
--   { -- hist state list that each contains one buffer
--      hbuf = <buf-handle>,
--      { -- windows list that display the same buffer
--         hwin = <win-handle>,
--         cursor_pos = { }, -- byte-based column
--         dir_mode = { },
--         lnums = { }, -- line number is 0-based
--         lcols = { }, -- byte-based column offset of each line
--         lines = { }, -- context to match hint of each line
--      },
--      ...
--   },
--   ...
--}
--
-- Some confusing column:
--   byte-based column: #line, strlen(), col(), getpos(), getcurpos(), nvim_win_get_cursor(), winsaveview().col
--   cell-based column: strwidth(), strdisplaywidth(), nvim_strwidth(), wincol(), winsaveview().leftcol
-- Take attention on that nvim_buf_set_extmark() and vim.regex:match_str() use byte-based buffer column.
-- To get exactly what's showing in window, use strchars() and strcharpart() which can handle multi-byte characters.
local function create_hint_states(opts)
  local hss = { } -- hint_states

  -- Current window as first item
  local cur_hwin = vim.api.nvim_get_current_win()
  local cur_hbuf = vim.api.nvim_win_get_buf(cur_hwin)
  hss[#hss + 1] = {
    hbuf = cur_hbuf,
    {
      hwin = cur_hwin,
      cursor_pos = vim.api.nvim_win_get_cursor(cur_hwin),
    }
  }

  -- Other windows of current tabpage
  if opts.multi_windows then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local b = vim.api.nvim_win_get_buf(w)
      if w ~= cur_hwin then

        -- Check duplicated buffers
        local hh = nil
        for _, _hh in ipairs(hss) do
          if b == _hh.hbuf then
            hh = _hh
            break
          end
        end

        if hh then
          hh[#hh + 1] = {
            hwin = w,
            cursor_pos = vim.api.nvim_win_get_cursor(w),
          }
        else
          hss[#hss + 1] = {
            hbuf = b,
            {
              hwin = w,
              cursor_pos = vim.api.nvim_win_get_cursor(w),
            }
          }
        end

      end
    end
  end

  return hss
end

-- Create hint lines from each windows to complete `hint_states` data
local function create_hint_winlines(hs, opts)
  -- get a bunch of information about the window and the cursor
  local hwin = hs.hwin
  local cursor_pos = hs.cursor_pos
  vim.api.nvim_set_current_win(hwin)
  vim.api.nvim_win_set_cursor(hwin, cursor_pos)
  local win_view = vim.fn.winsaveview()
  local win_info = vim.fn.getwininfo(hwin)[1]
  local top_line = win_info.topline - 1 -- `getwininfo` use 1-based line number
  local bot_line = win_info.botline - 1 -- `getwininfo` use 1-based line number

  -- adjust the visible part of the buffer to hint based on the direction
  local direction = opts.direction
  local direction_mode = nil
  if direction == constants.HintDirection.BEFORE_CURSOR then
    bot_line = cursor_pos[1] - 1 -- `nvim_win_get_cursor()` use 1-based line number
    direction_mode = { cursor_col = cursor_pos[2], direction = direction }
  elseif direction == constants.HintDirection.AFTER_CURSOR then
    top_line = cursor_pos[1] - 1 -- `nvim_win_get_cursor()` use 1-based line number
    direction_mode = { cursor_col = cursor_pos[2], direction = direction }
  end
  hs.dir_mode = direction_mode

  -- NOTE: due to an (unknown yet) bug in neovim, the sign_width is not correctly reported when shifting the window
  -- view inside a non-wrap window, so we can’t rely on this; for this reason, we have to implement a weird hack that
  -- is going to disable the signs while hop is running (I’m sorry); the state is restored after jump
  -- local left_col_offset = win_info.variables.context.number_width + win_info.variables.context.sign_width
  -- hack to get the left column offset in nowrap
  local win_rightcol = nil
  if not vim.wo.wrap then
    vim.api.nvim_win_set_cursor(hwin, { cursor_pos[1], 0 })
    win_rightcol = win_view.leftcol + (win_info.width - (vim.fn.wincol() - 1))
    vim.fn.winrestview(win_view)
  end

  -- get the buffer lines
  hs.lnums = {}
  hs.lcols = {}
  hs.lines = {}
  local lnr = top_line
  while lnr <= bot_line do
      table.insert(hs.lnums, lnr)
      local fold_end = vim.fn.foldclosedend(lnr + 1) -- `foldclosedend()` use 1-based line number
      if fold_end == -1 then
        -- save line number and sliced line text to hint
        local cur_line = vim.fn.getline(lnr + 1) -- `getline()` use 1-based line number
        local cur_cols = win_view.leftcol
        if win_rightcol then
          if win_view.leftcol >= vim.api.nvim_strwidth(cur_line) then
            -- constants.HintLineException.EMPTY_LINE means empty line and only col=1 can jump to
            cur_line = constants.HintLineException.EMPTY_LINE
          else
            local cidx0 = str_col2char(cur_line, win_view.leftcol)
            local cidx1 = str_col2char(cur_line, win_rightcol)
            cur_cols = #vim.fn.strcharpart(cur_line, 0, cidx0)
            cur_line = vim.fn.strcharpart(cur_line, cidx0, cidx1 - cidx0)
          end
        end
        table.insert(hs.lcols, cur_cols)
        table.insert(hs.lines, cur_line)
        lnr = lnr + 1
      else
        -- skip fold lines and only col=1 can jump to at fold lines
        table.insert(hs.lcols, win_view.leftcol)
        table.insert(hs.lines, constants.HintLineException.EMPTY_LINE)
        lnr = fold_end
      end
  end
end

-- Crop duplicated hint lines area  from `hc` compared with `hp`
local function crop_winlines(hc, hp)
  if hc.lnums[#hc.lnums] < hp.lnums[1] or hc.lnums[1] > hp.lnums[#hp.lnums] then
    return
  end

  local ci = 1         -- start line index of hc
  local ce = #hc.lnums -- end line index of hc
  local pi = 1         -- start line index of hp
  local pe = #hp.lnums -- end line index of hp

  while ci <= ce and pi <= pe do
    if hc.lnums[ci] < hp.lnums[pi] then
      ci = ci + 1
    elseif hc.lnums[ci] > hp.lnums[pi] then
      pi = pi + 1
    elseif hc.lnums[ci] == hp.lnums[pi] then
      if (hc.lines[ci] ~= constants.HintLineException.EMPTY_LINE) and
         (hp.lines[pi] ~= constants.HintLineException.EMPTY_LINE) then
        local cl = hc.lcols[ci]       -- left byte-based column of ci line
        local cr = cl + #hc.lines[ci] -- right byte-based column of ci line
        local pl = hp.lcols[pi]       -- left byte-based column of pi line
        local pr = pl + #hp.lines[pi] -- right byte-based column of pi line

        if cl >= pr or cr <= pl then
          -- Must keep this empty block to guarantee other elseif-condition correct
          -- Must compare cl-pl prior than cl-pr at elseif-condition
        elseif cl < pl and cr < pr then
          -- p:    ******
          -- c: ******
          hc.lines[ci] = string.sub(hc.lines[ci], 1, pl)
        elseif cl <= pl and cr >= pr then
          -- p:    ******
          -- c: ************
          hp.lines[pi] = hc.lines[ci]
          hp.lcols[pi] = hc.lcols[ci]
          hc.lines[ci] = constants.HintLineException.INVALID_LINE
        elseif cl < pr and cr > pr then
          -- p: ******
          -- c:    ******
          hc.lines[ci] = string.sub(hc.lines[ci], pr)
        elseif cl < pr and cr < pr then
          -- p: ************
          -- c:    ******
          hc.lines[ci] = constants.HintLineException.INVALID_LINE
        end
      elseif (hc.lines[ci] == constants.HintLineException.EMPTY_LINE) and
             (hp.lines[pi] == constants.HintLineException.EMPTY_LINE) then
          hc.lines[ci] = constants.HintLineException.INVALID_LINE
      end

      ci = ci + 1
      pi = pi + 1
    end
  end
end

-- Create hint lines from each buffer to complete `hint_states` data
local function create_hint_buflines(hh, opts)
  for _, hs in ipairs(hh) do
    create_hint_winlines(hs, opts)
  end

  -- Remove inter-covered area of different windows with same buffer.
  -- Iterate reverse to guarantee the first window has the max area.
  for c = #hh, 1, -1 do
    for p = 1, c-1 do
      crop_winlines(hh[c], hh[p])
    end
  end
end

local function hint_with(hint_mode, opts, _hint_states)
  local hl_ns = vim.api.nvim_create_namespace('')
  local hint_states
  if _hint_states then
    hint_states = _hint_states
  else
    hint_states = create_hint_states(opts)
    for _, hh in ipairs(hint_states) do
      create_hint_buflines(hh, opts)
    end
    vim.api.nvim_set_current_win(hint_states[1][1].hwin)
  end

  -- Create call hints for all windows from hint_states
  local hints = hint_mode:get_hint_list(hint_states, opts)

  if #hints == 0 then
    eprintln(' -> there’s no such thing we can see…', opts.teasing)
    return
  elseif opts.jump_on_sole_occurrence and #hints == 1 then
    -- search the hint and jump to it
    local h = hints[1]
    vim.api.nvim_set_current_win(h.handle.w)
    vim.api.nvim_win_set_cursor(h.handle.w, { h.line + 1, h.col - 1})
    return
  end

  -- mutate hint_list to add character targets
  hint.assign_character_targets(hints, opts)

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

local function get_pattern(prompt, maxchar, opts)
  local hl_ns = nil
  local hint_states = nil
  -- Create hint states for pattern preview
  if opts then
    hl_ns = vim.api.nvim_create_namespace('')
    hint_states = create_hint_states(opts)
    for _, hh in ipairs(hint_states) do
      create_hint_buflines(hh, opts)
    end
    vim.api.nvim_set_current_win(hint_states[1][1].hwin)
  end

  local K_Esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  local K_BS = vim.api.nvim_replace_termcodes('<BS>', true, false, true)
  local K_CR = vim.api.nvim_replace_termcodes('<CR>', true, false, true)
  local pat_keys = {}
  local pat = ''
  while (true) do
    pat = vim.fn.join(pat_keys, '')
    if opts then
      -- Preview the pattern in highlight
      grey_things_out(hl_ns, hint_states)
      if #pat > 0 then
        highlight_things_out(hl_ns, hint_states, hint.by_case_searching(pat, false, opts))
      end
    end
    vim.api.nvim_echo({}, false, {})
    vim.cmd('redraw')
    vim.api.nvim_echo({{prompt, 'Question'}, {pat}}, false, {})

    local ok, key = pcall(vim.fn.getchar)
    if not ok then break end -- Interrupted by <C-c>

    if type(key) == 'number' then
      key = vim.fn.nr2char(key)
    elseif key:byte() == 128 then
      -- It's a special key in string
    end

    if key == K_Esc then
      pat = nil
      break
    elseif key == K_CR then
      break
    elseif key == K_BS then
      pat_keys[#pat_keys] = nil
    else
      pat_keys[#pat_keys + 1] = key
    end

    if maxchar and #pat_keys >= maxchar then
      pat = vim.fn.join(pat_keys, '')
      break
    end
  end
  if opts then
    M.quit(hl_ns, hint_states)
  end
  vim.api.nvim_echo({}, false, {})
  vim.cmd('redraw')
  return pat, hint_states
end

-- Refine hints in the given buffer.
--
-- Refining hints allows to advance the state machine by one step. If a terminal step is reached, this function jumps to
-- the location. Otherwise, it stores the new state machine.
function M.refine_hints(key, teasing, hl_ns, hint_states, hints)
  local h, update_hints = hint.reduce_hints(hints, key)

  if h == nil then
    if #update_hints == 0 then
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
    vim.api.nvim_win_set_cursor(h.handle.w, { h.line + 1, h.col - 1})
  end

  return h, update_hints
end

-- Quit Hop and delete its resources.
function M.quit(hl_ns, hint_states)
  for _, hh in ipairs(hint_states) do
    clear_namespace(hh.hbuf, hl_ns)
  end
end

function M.hint_words(opts)
  hint_with(hint.by_word_start, get_command_opts(opts))
end

function M.hint_patterns(opts, pattern)
  opts = get_command_opts(opts)

  -- The pattern to search is either retrieved from the (optional) argument
  -- or directly from user input.
  local pat, hss
  if pattern then
    pat = pattern
  else
    vim.fn.inputsave()
    pat, hss = get_pattern('Hop pattern: ', nil, opts)
    vim.fn.inputrestore()
    if not pat then return end
  end

  if #pat == 0 then
    eprintln('-> empty pattern', opts.teasing)
    return
  end

  hint_with(hint.by_case_searching(pat, false, opts), opts, hss)
end

function M.hint_char1(opts)
  opts = get_command_opts(opts)
  local c = get_pattern('Hop 1 char: ', 1)
  if c then
    hint_with(hint.by_case_searching(c, true, opts), opts)
  end
end

function M.hint_char2(opts)
  opts = get_command_opts(opts)
  local c = get_pattern('Hop 2 char: ', 2)
  if c then
    hint_with(hint.by_case_searching(c, true, opts), opts)
  end
end

function M.hint_lines(opts)
  hint_with(hint.by_line_start, get_command_opts(opts))
end

function M.hint_lines_skip_whitespace(opts)
  hint_with(hint.by_line_start_skip_whitespace, get_command_opts(opts))
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

local constants = require'hop.constants'
local ui_util = require'hop.ui_util'

local M = {}

-- Create hint lines from each windows to complete `hint_states` data
local function create_hint_winlines(hs, direction)
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

  -- 0-based cell index of the leftmost visible character
  local win_leftcol = win_view.leftcol
  -- 0-based cell index of the rightmost visible character if nowrap, nil otherwise
  local win_rightcol = nil
  if not vim.wo.wrap then
    vim.api.nvim_win_set_cursor(hwin, { cursor_pos[1], 0 })
    local true_width = (win_info.width - (vim.fn.wincol() - 1))
    win_rightcol = win_leftcol + true_width - 1
    vim.fn.winrestview(win_view)
  end

  -- get the buffer lines
  -- this line number
  hs.lnums = {}
  -- 0-based byte index of the leftmost character in this line
  hs.lcols = {}
  -- this line string
  hs.lines = {}
  local lnr = top_line
  while lnr <= bot_line do
      table.insert(hs.lnums, lnr)
      local fold_end = vim.fn.foldclosedend(lnr + 1) -- `foldclosedend()` use 1-based line number
      if fold_end == -1 then
        -- save line number and sliced line text to hint
        local cur_line = vim.fn.getline(lnr + 1) -- `getline()` use 1-based line number
        local cur_cols = 0
        -- 0-based cell index of last character in cur_line
        local last_idx = vim.api.nvim_strwidth(cur_line) - 1
        if win_rightcol then
          if win_leftcol > last_idx then
            -- constants.HintLineException.EMPTY_LINE means empty line and only col=1 can jump to
            cur_cols = -1
            cur_line = constants.HintLineException.EMPTY_LINE
          else
            -- 0-based byte index of leftmost visible character in line
            local cidx0 = vim.fn.byteidx(cur_line, win_leftcol)
            -- 0-based byte index of rightmost visible character in line
            local cidx1 = win_rightcol <= last_idx
              and vim.fn.byteidx(cur_line, win_rightcol) or vim.fn.byteidx(cur_line, last_idx)
            cur_cols = cidx0
            cur_line = cur_line:sub(cidx0 + 1, cidx1 + 1)
          end
        end

        -- adjust line and start col for direction
        if lnr == top_line then
          if direction_mode and direction == constants.HintDirection.AFTER_CURSOR then
            local start_col = direction_mode.cursor_col
            local new_offset = start_col - cur_cols
            if new_offset > 0 then
              cur_line = cur_line:sub(new_offset + 1)
              cur_cols = start_col
            end
          end
        elseif lnr == bot_line then
          if direction_mode and direction == constants.HintDirection.BEFORE_CURSOR then
            local end_col = direction_mode.cursor_col
            local new_offset = end_col - cur_cols
            if new_offset >= 0 then
              cur_line = cur_line:sub(1, new_offset)
            end
          end
        end
        table.insert(hs.lcols, cur_cols)
        table.insert(hs.lines, cur_line)
        lnr = lnr + 1
      else
        -- skip fold lines and only col=1 can jump to at fold lines
        table.insert(hs.lcols, -1)
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
      if (hc.lines[ci] == constants.HintLineException.INVALID_LINE) or
         (hp.lines[pi] == constants.HintLineException.INVALID_LINE) then
         goto next
      end
      if (type(hc.lines[ci]) == "string") and (type(hp.lines[pi]) == "string") then
        local cl = hc.lcols[ci]       -- leftmost 0-based byte index of ci line
        local cr = cl + #hc.lines[ci] - 1 -- rightmost 0-based byte index of ci line
        local pl = hp.lcols[pi]       -- leftmost 0-based byte index of pi line
        local pr = pl + #hp.lines[pi] - 1 -- rightmost 0-based byte index of pi line

        if cl > pr or cr < pl then
          -- Must keep this empty block to guarantee other elseif-condition correct
          -- Must compare cl-pl prior than cl-pr at elseif-condition
        elseif cl <= pl and cr <= pr then
          -- p:    ******
          -- c: ******
          hc.lines[ci] = string.sub(hc.lines[ci], 1, pl - cl)
        elseif cl <= pl and cr >= pr then
          -- p:    ******
          -- c: ************
          hp.lines[pi] = hc.lines[ci]
          hp.lcols[pi] = hc.lcols[ci]
          hc.lines[ci] = constants.HintLineException.INVALID_LINE
        elseif cl <= pr and cr >= pr then
          -- p: ******
          -- c:    ******
          hc.lcols[ci] = pr + 1
          hc.lines[ci] = string.sub(hc.lines[ci], pr - cl + 2)
        elseif cl <= pr and cr <= pr then
          -- p: ************
          -- c:    ******
          hc.lines[ci] = constants.HintLineException.INVALID_LINE
        end
      elseif (hc.lines[ci] == constants.HintLineException.EMPTY_LINE) and
             (hp.lines[pi] == constants.HintLineException.EMPTY_LINE) then
          hc.lines[ci] = constants.HintLineException.INVALID_LINE
      end

      ::next::
      ci = ci + 1
      pi = pi + 1
    end
  end
end

-- Create hint lines from each buffer to complete `hint_states` data
local function create_hint_buflines(hh, direction)
  for _, hs in ipairs(hh) do
    create_hint_winlines(hs, direction)
  end

  -- Remove inter-covered area of different windows with same buffer.
  -- Iterate reverse to guarantee the first window has the max area.
  for c = #hh, 1, -1 do
    for p = 1, c-1 do
      crop_winlines(hh[c], hh[p])
    end
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
function M.create_hint_states(windows, direction)
  local hss = { } -- hint_states

  local cur_hwin = vim.api.nvim_get_current_win()

  for _, w in ipairs(windows) do
    local b = vim.api.nvim_win_get_buf(w)
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

  for _, hh in ipairs(hss) do
    create_hint_buflines(hh, direction)
  end

  vim.api.nvim_set_current_win(cur_hwin)

  return hss
end

function M.get_grey_out(hint_states)
  local grey_out = {}
  for _, hh in ipairs(hint_states) do
    local hl_buf_data = {}
    hl_buf_data.buf = hh.hbuf
    local ranges = {}
    hl_buf_data.ranges = ranges

    local function add_range(line, col_start, col_end)
      ranges[#ranges + 1] = {line = line, col_start = col_start, col_end = col_end}
    end

    for _, hs in ipairs(hh) do
      -- Highlight unmatched lines
      if hs.dir_mode ~= nil then
        if hs.dir_mode.direction == constants.HintDirection.AFTER_CURSOR then
          -- Hightlight lines after cursor
          add_range(hs.lnums[1], hs.dir_mode.cursor_col, -1)
          for k = 2, #hs.lnums do
            add_range(hs.lnums[k], 0, -1)
          end
        elseif hs.dir_mode.direction == constants.HintDirection.BEFORE_CURSOR then
          -- Hightlight lines before cursor
          for k = 1, #hs.lnums - 1 do
            add_range(hs.lnums[k], 0, -1)
          end
          add_range(hs.lnums[#hs.lnums], 0, hs.dir_mode.cursor_col)
        end
      else
        -- Hightlight all lines
        for _, lnr in ipairs(hs.lnums) do
          add_range(lnr, 0, -1)
        end
      end
    end

    grey_out[#grey_out + 1] = hl_buf_data
  end

  return grey_out
end

-- I hate Lua.
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, vim.fn.byteidx(s, 1))
  return f:upper() == f
end

function M.format_pat(pat, opts)
  opts = opts or {}

  local ori = pat
  if opts.plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end

  -- append dict pattern for each char in `pat`
  if opts.dict_list then
    local dict_pat = ''
    for i = 1, #ori do
      local char = ori:sub(i, i)
      local dict_char_pat = ''
      -- checkout dict-char pattern from each dict
      for _, v in ipairs(opts.dict_list) do
        local val = require('hop.dict.' .. v)[char]
        if val ~= nil then
          dict_char_pat = dict_char_pat .. val
        end
      end
      -- make sure that there are one dict support `char` at least
      if dict_char_pat == '' then
        dict_pat = ''
        break
      end
      dict_pat = dict_pat .. '['.. dict_char_pat .. ']'
    end
    if dict_pat ~= '' then
      pat = string.format([[\(%s\)\|\(%s\)]], pat, dict_pat)
    end
  end

  if not opts.no_smartcase and vim.o.smartcase then
    if not starts_with_uppercase(ori) then
      pat = '\\c' .. pat
    end
  elseif opts.case_insensitive then
    pat = '\\c' .. pat
  end

  return vim.regex(pat)
end

-- Hint modes follow.
-- a hint mode should define a get_hint_list function that returns a list of {line, col} positions for hop targets.

function M.get_pattern(prompt, maxchar, opts, hint_states)
  local hl_ns = nil
  -- Create hint states for pattern preview
  if opts then
    hl_ns = vim.api.nvim_create_namespace('')
  end

  local K_Esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  local K_BS = vim.api.nvim_replace_termcodes('<BS>', true, false, true)
  local K_CR = vim.api.nvim_replace_termcodes('<CR>', true, false, true)
  local pat_keys = {}
  local bufs, hints = {}, nil
  local hint_opts = {grey_out = M.get_grey_out(hint_states)}
  local pat = ''

  vim.fn.inputsave()

  while (true) do
    pat = vim.fn.join(pat_keys, '')
    if opts then
      ui_util.clear_all_ns(hl_ns)
      -- Preview the pattern in highlight
      ui_util.grey_things_out(hl_ns, hint_opts)
      if #pat > 0 then
        hints = M.create_hint_list_by_scanning_lines(M.format_pat(pat, opts), hint_states, false)
        ui_util.highlight_things_out(hl_ns, hints)
      end
    end
    vim.api.nvim_echo({}, false, {})
    vim.cmd('redraw')
    vim.api.nvim_echo({{prompt, 'Question'}, {pat}}, false, {})

    local ok, key = pcall(vim.fn.getchar)
    if not ok then -- Interrupted by <C-c>
      pat = nil
      break
    end

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
    ui_util.clear_all_ns(hl_ns)
  end
  vim.api.nvim_echo({}, false, {})
  vim.cmd('redraw')

  vim.fn.inputrestore()

  if #pat == 0 then
    ui_util.eprintln('-> empty pattern', opts.teasing)
    return
  end

  if not hints then hints = M.create_hint_list_by_scanning_lines(M.format_pat(pat, opts), hint_states, false) end

  return hints
end

-- Mark the current line with hints for the given hint mode.
--
-- This function applies reg repeatedly until it fails (typically at the end of
-- the line). For every match of the regex, a hint placeholder is generated, which
-- contains two fields giving the line and hint column of the hint:
--
--   { line, col }
--
-- The input line_nr is the line number of the line currently being marked.
--
-- This function returns the list of hints
function M.mark_hints_line(re, line_nr, line, col_offset, oneshot)
  local hints = {}
  local shifted_line = line

  -- if no text at line, we can only jump to col=1 when col_offset=0 and hint mode can match empty text
  if type(shifted_line) == "number" then
    if (shifted_line == constants.HintLineException.EMPTY_LINE) and
       (col_offset == 0) and
       (re:match_str('')) ~= nil then
      hints[#hints + 1] = {
        line = line_nr + 1; -- use 1-indexed line
        col = 1;
        col_end = 0,
      }
    end
    return hints
  end

  -- modify the shifted line to take the direction mode into account, if any
  local col_bias = col_offset

  local col = 1
  while true do
    local s = shifted_line:sub(col)
    local b, e = re:match_str(s)

    if b == nil then
      break
    end

    hints[#hints + 1] = {
      line = line_nr + 1;
      col = col_bias + col + b;
      col_end = col_bias + col + e;
    }

    if oneshot then
      break
    else
      col = col + e
    end
  end

  return hints
end

-- Manhattan distance with column and row, weighted on x so that results are more packed on y.
local function manh_dist(a, b, x_bias)
  local bias = x_bias or 10
  return bias * math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
end

-- Create hints for a given indexed line.
--
-- This function is used in M.create_hints to apply the hints to all the visible lines in the buffer. The need for such
-- a specialized function is made real because of the possibility to have variations of hinting functions that will also
-- work in a given direction, requiring a more granular control at the line level.
--
-- Then hs argument is the item of `hint_states`.
local function create_hints_for_line(
  i,
  hint_list,
  re,
  hbuf,
  hs,
  window_dist,
  oneshot
)
  local hints = M.mark_hints_line(re, hs.lnums[i], hs.lines[i], hs.lcols[i], oneshot)
  for _, hint in pairs(hints) do
    hint.buf = hbuf

    -- extra metadata
    hint.dist = manh_dist(hs.cursor_pos, {hint.line, hint.col - 1})
    hint.wdist = window_dist
    hint.win = hs.hwin

    hint_list[#hint_list+1] = hint
  end
end

function M.create_hint_list_by_scanning_lines(re, hint_states, oneshot)
  -- extract all the words currently visible on screen; the hints variable contains the list
  -- of words as a pair of { line, column } for each word on a given line and indirect_words is a
  -- simple list containing { line, word_index, distance_to_cursor } that is sorted by distance to
  -- cursor, allowing to zip this list with the hints and distribute the hints
  local hints = {}

  local winpos = vim.api.nvim_win_get_position(0)
  for _, hh in ipairs(hint_states) do
    local hbuf = hh.hbuf
    for _, hs in ipairs(hh) do
      local window_dist = manh_dist(winpos, vim.api.nvim_win_get_position(hs.hwin))
      for i = 1, #hs.lines do
        create_hints_for_line(i, hints, re, hbuf, hs, window_dist, oneshot)
      end
    end
  end
  return hints
end

M.comparators = {}

M.comparators.win_cursor_dist_comparator = function(a, b)
  if a.wdist < b.wdist then
    return true
  elseif a.wdist > b.wdist then
    return false
  else
    if a.dist < b.dist then
      return true
    end
  end
end

M.callbacks = {}

M.callbacks.win_goto = function(hint)
  -- prior to jump, register the current position into the jump list
  vim.cmd("normal! m'")

  vim.api.nvim_set_current_win(hint.win)
  vim.api.nvim_win_set_cursor(hint.win, {hint.line, hint.col - 1})
end
return M

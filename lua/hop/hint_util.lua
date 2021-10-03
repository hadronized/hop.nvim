local constants = require'hop.constants'
local ui_util = require'hop.ui_util'

local M = {}

-- Create hint lines from each windows to complete `views_data` data
---@param hs ViewsWinData @the view data to populate
---@param direction HintDirection
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
  if direction == constants.HintDirection.BEFORE_CURSOR then
    bot_line = cursor_pos[1] - 1 -- `nvim_win_get_cursor()` use 1-based line number
  elseif direction == constants.HintDirection.AFTER_CURSOR then
    top_line = cursor_pos[1] - 1 -- `nvim_win_get_cursor()` use 1-based line number
  end

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
  hs.lines_data = {}
  local lnr = top_line
  while lnr <= bot_line do
    local fold_end = vim.fn.foldclosedend(lnr + 1) -- `foldclosedend()` use 1-based line number
    local cur_line, cur_cols
    if fold_end == -1 then
      -- save line number and sliced line text to hint
      cur_line = vim.fn.getline(lnr + 1) -- `getline()` use 1-based line number
      cur_cols = 0
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
        if direction == constants.HintDirection.AFTER_CURSOR then
          local start_col = cursor_pos[2]
          local new_offset = start_col - cur_cols
          if new_offset > 0 then
            cur_line = cur_line:sub(new_offset + 1)
            cur_cols = start_col
          end
        end
      elseif lnr == bot_line then
        if direction == constants.HintDirection.BEFORE_CURSOR then
          local end_col = cursor_pos[2]
          local new_offset = end_col - cur_cols
          if new_offset >= 0 then
            cur_line = cur_line:sub(1, new_offset)
          end
        end
      end
      lnr = lnr + 1
    else
      -- skip fold lines and only col=1 can jump to at fold lines
      cur_cols = -1
      cur_line = constants.HintLineException.EMPTY_LINE
      lnr = fold_end
    end

    local line_data = {
      line_number = lnr,
      col_start = cur_cols,
      line = cur_line,
    }

    table.insert(hs.lines_data, line_data)
  end
end

---Crop duplicated hint lines area  from `hc` compared with `hp`
---@param hc LineData[] @line data that can be cropped
---@param hp LineData[] @line data to crop with
local function crop_winlines(hc, hp)
  if hc[#hc].line_number < hp[1].line_number or hc[1].line_number > hp[#hp].line_number then
    return
  end

  local ci = 1         -- start line index of hc
  local pi = 1         -- start line index of hp

  while ci <= #hc and pi <= #hp do
    local lc, lp = hc[ci], hp[pi]
    if lc.line_number < lp.line_number then
      ci = ci + 1
    elseif lc.line_number > lp.line_number then
      pi = pi + 1
    elseif lc.line_number == lp.line_number then
      if (lc.line == constants.HintLineException.INVALID_LINE) or
         (lp.line == constants.HintLineException.INVALID_LINE) then
         goto next
      end
      if (type(lc.line) == "string") and (type(lp.line) == "string") then
        local cl = lc.col_start       -- leftmost 0-based byte index of ci line
        local cr = cl + #lc.line - 1  -- rightmost 0-based byte index of ci line
        local pl = lp.col_start       -- leftmost 0-based byte index of pi line
        local pr = pl + #lp.line - 1  -- rightmost 0-based byte index of pi line

        if cl > pr or cr < pl then
          -- Must keep this empty block to guarantee other elseif-condition correct
          -- Must compare cl-pl prior than cl-pr at elseif-condition
        elseif cl <= pl and cr <= pr then
          -- p:    ******
          -- c: ******
          lc.line = string.sub(lc.line, 1, pl - cl)
          if #lc.line == 0 then
            lc.line = constants.HintLineException.INVALID_LINE
          end
        elseif cl <= pl and cr >= pr then
          -- p:    ******
          -- c: ************
          -- we want to split c in two, cropping out the middle

          ---@type LineData
          local left_cropped = {
            col_start = cl,
            line = lc.line:sub(1, pl - cl),
            line_number = lc.line_number
          }
          if #left_cropped.line == 0 then left_cropped.line = constants.HintLineException.INVALID_LINE end
          ---@type LineData
          local right_cropped = nil
          if cr > pr then
            right_cropped = {
              col_start = pr + 1,
              line = lc.line:sub((pr + 2) - cl),
              line_number = lc.line_number
            }
          end
          hc[ci] = left_cropped
          if right_cropped then
            table.insert(hc, ci + 1, right_cropped)
            ci = ci + 1
          end
        elseif cl <= pr and cr >= pr then
          -- p: ******
          -- c:    ******
          lc.col_start = pr + 1
          lc.line = string.sub(lc.line, pr - cl + 2)
        elseif cl <= pr and cr <= pr then
          -- p: ************
          -- c:    ******
          lc.line = constants.HintLineException.INVALID_LINE
        end
      elseif (lc.line == constants.HintLineException.EMPTY_LINE) and
             (lp.line == constants.HintLineException.EMPTY_LINE) then
          lc.line = constants.HintLineException.INVALID_LINE
      end

      ::next::
      ci = ci + 1
      pi = pi + 1
    end
  end
end

---Create hint lines from each buffer to complete `views_data` data
---@param hh ViewsData @view data to complete
---@param direction HintDirection @direction to use to complete data
local function create_hint_buflines(hh, direction)
  local wins_data = hh.wins_data
  for _, hs in ipairs(wins_data) do
    -- populate lines_data
    create_hint_winlines(hs, direction)
  end

  -- Remove inter-covered area of different windows with same buffer.
  -- Iterate reverse to guarantee the first window has the max area.
  for c = #wins_data, 1, -1 do
    for p = 1, c-1 do
      crop_winlines(wins_data[c].lines_data, wins_data[p].lines_data)
    end
  end
end

---Describes a "view" on a line in a buffer.
---@class LineData
---@field line_number number @1-indexed line number of this line in its buffer
---@field col_start number @0-indexed, byte-based column position where this line view starts
---@field line string|HintLineException @the contents of this line view

---To contain any possibly relevant data about all this view on a buffer.
---@class ViewsWinData
---@field hwin number @the window
---@field cursor_pos table @(1,0)-indexed cursor position within this window
---@field lines_data LineData[] @line data for this view on the buffer

---To contain any possibly relevant data about all the views on a buffer.
---@class ViewsData
---@field hbuf number @the buffer whose views we are considering
---@field wins_data ViewsWinData[] @list of the data by window

-- Some confusing column:
--   byte-based column: #line, strlen(), col(), getpos(), getcurpos(), nvim_win_get_cursor(), winsaveview().col
--   cell-based column: strwidth(), strdisplaywidth(), nvim_strwidth(), wincol(), winsaveview().leftcol
-- Take attention on that nvim_buf_set_extmark() and vim.regex:match_str() use byte-based buffer column.
-- To get exactly what's showing in window, use strchars() and strcharpart() which can handle multi-byte characters.

---Gathers information on the views on buffers in the given set of windows that could be relevant to hinting, 
---taking the given direction into account.
---@param windows number[] @window handles to collect information for
---@param direction HintDirection @direction to use to restrict the scope of the information returned
---@return ViewsData @a data structure containing the retrieved information
function M.create_views_data(windows, direction)
  ---@type ViewsData[]
  local hss = { } -- views_data

  local cur_hwin = vim.api.nvim_get_current_win()

  for _, w in ipairs(windows) do
    local b = vim.api.nvim_win_get_buf(w)
    ---@type ViewsData
    local hh = nil

    -- Check duplicated buffers
    ---@param _hh ViewsData
    for _, _hh in ipairs(hss) do
      if b == _hh.hbuf then
        hh = _hh
        break
      end
    end

    if hh then
      local wins_data = hh.wins_data
      wins_data[#wins_data + 1] = {
        hwin = w,
        cursor_pos = vim.api.nvim_win_get_cursor(w),
      }
    else
      hss[#hss + 1] = {
        hbuf = b,
        wins_data = {{
          hwin = w,
          cursor_pos = vim.api.nvim_win_get_cursor(w),
        }}
      }
    end
  end

  for _, hh in ipairs(hss) do
    create_hint_buflines(hh, direction)
  end

  vim.api.nvim_set_current_win(cur_hwin)

  return hss
end

function M.get_grey_out(views_data)
  local grey_out = {}
  for _, hh in ipairs(views_data) do
    local hl_buf_data = {}
    hl_buf_data.buf = hh.hbuf
    local ranges = {}
    hl_buf_data.ranges = ranges

    for _, hs in ipairs(hh.wins_data) do
      -- Hightlight all lines
      for _, line_data in ipairs(hs.lines_data) do
        local line_number = line_data.line_number - 1
        local col_start = line_data.col_start
        local col_end = type(line_data.line) == "string" and line_data.col_start + #line_data.line or -1
        ranges[#ranges + 1] = {start = {line_number, col_start}, ['end'] = {line_number, col_end}}
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

function M.get_pattern(prompt, maxchar, opts, views_data)
  local hl_ns = nil
  -- Create hint states for pattern preview
  if opts then
    hl_ns = vim.api.nvim_create_namespace('')
  end

  local K_Esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  local K_BS = vim.api.nvim_replace_termcodes('<BS>', true, false, true)
  local K_CR = vim.api.nvim_replace_termcodes('<CR>', true, false, true)
  local pat_keys = {}
  local hints = nil
  local hint_opts = {grey_out = M.get_grey_out(views_data)}
  local pat = ''

  vim.fn.inputsave()

  while (true) do
    pat = vim.fn.join(pat_keys, '')
    if opts then
      -- Preview the pattern in highlight
      if hint_opts.grey_out then
        ui_util.grey_things_out(hl_ns, hint_opts.grey_out)
      end
      if #pat > 0 then
        hints = M.create_hint_list_by_scanning_lines(M.format_pat(pat, opts), views_data, false)
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

  if not pat then return end

  if #pat == 0 then
    ui_util.eprintln('-> empty pattern', opts.teasing)
    return
  end

  if not hints then hints = M.create_hint_list_by_scanning_lines(M.format_pat(pat, opts), views_data, false) end

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
        line = line_nr; -- use 1-indexed line
        col = 1;
        col_end = 0,
      }
    end
    return hints
  end

  local col_bias = col_offset

  local col = 1
  while true do
    local s = shifted_line:sub(col)
    local b, e = re:match_str(s)

    if b == nil then
      break
    end

    hints[#hints + 1] = {
      line = line_nr;
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

function M.create_hint_list_by_scanning_lines(re, views_data, oneshot)
  -- extract all the words currently visible on screen; the hints variable contains the list
  -- of words as a pair of { line, column } for each word on a given line and indirect_words is a
  -- simple list containing { line, word_index, distance_to_cursor } that is sorted by distance to
  -- cursor, allowing to zip this list with the hints and distribute the hints
  local hints = {}

  local winpos = vim.api.nvim_win_get_position(0)
  for _, hh in ipairs(views_data) do
    local hbuf = hh.hbuf
    for _, hs in ipairs(hh.wins_data) do
      local window_dist = manh_dist(winpos, vim.api.nvim_win_get_position(hs.hwin))
      for i = 1, #hs.lines_data do
        local line_data = hs.lines_data[i]
        local new_hints = M.mark_hints_line(re, line_data.line_number, line_data.line,
          line_data.col_start, oneshot)
        for _, hint in pairs(new_hints) do
          hint.buf = hbuf

          -- extra metadata
          hint.dist = manh_dist(hs.cursor_pos, {hint.line, hint.col - 1})
          hint.wdist = window_dist
          hint.win = hs.hwin
        end
        vim.list_extend(hints, new_hints)
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

local perm = require'hop.perm'
local constants = require'hop.constants'
local util = require'hop.hint_util'
local ui_util = require'hop.ui_util'

local M = {}

-- I hate Lua.
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, vim.fn.byteidx(s, 1))
  return f:upper() == f
end

local function format_pat(pat, opts)
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

local function get_pattern(prompt, maxchar, opts, hint_states)
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
  local hint_opts = {grey_out = util.get_grey_out(hint_states)}
  local pat = ''

  vim.fn.inputsave()

  while (true) do
    pat = vim.fn.join(pat_keys, '')
    if opts then
      ui_util.clear_all_ns(hl_ns, bufs, hint_opts)
      -- Preview the pattern in highlight
      ui_util.grey_things_out(hl_ns, hint_opts)
      if #pat > 0 then
        hints = M.create_hint_list_by_scanning_lines(format_pat(pat, opts), hint_states, false)
        bufs = ui_util.highlight_things_out(hl_ns, hints)
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
    ui_util.clear_all_ns(hl_ns, bufs, hint_opts)
  end
  vim.api.nvim_echo({}, false, {})
  vim.cmd('redraw')

  vim.fn.inputrestore()

  if #pat == 0 then
    ui_util.eprintln('-> empty pattern', opts.teasing)
    return
  end

  if not hints then hints = M.create_hint_list_by_scanning_lines(format_pat(pat, opts), hint_states, false) end

  return hints
end

function M.by_pattern(prompt, max_chars, opts)
  opts = opts or {}

  local strategy = {}
  strategy.get_hint_list = function()
    local hint_states = util.create_hint_states(opts.multi_windows, opts.direction)
    return get_pattern(prompt, max_chars, opts.preview and opts, hint_states), {grey_out = util.get_grey_out(hint_states)}
  end
  return strategy
end

-- Used to hint result of a search.
function M.by_searching(pat, opts)
  opts = opts or {}

  local re = format_pat(pat, opts)

  local strategy = {}
  strategy.get_hint_list = function()
    local hint_states = util.create_hint_states(opts.multi_windows, opts.direction)
    return M.create_hint_list_by_scanning_lines(re, hint_states, opts.oneshot),
      {grey_out = util.get_grey_out(hint_states)}
  end
  return strategy
end

-- Word hint mode.
--
-- Used to tag words with hints, its behaviour depends on the
-- iskeyword value.
-- M.by_word_start = M.by_searching('\\<\\k\\+')
M.by_word_start = function(opts)
  opts = opts or {}
  opts.no_smartcase = true
  return M.by_searching('\\k\\+', opts)
end

M.by_any_pattern = function (opts)
  opts = opts or {}
  opts.preview = true
  return M.by_pattern("Hop pattern: ", nil, opts)
end

M.by_char1_pattern = function (opts)
  opts = opts or {}
  return M.by_pattern("Hop 1 char: ", 1, opts)
end

M.by_char2_pattern = function (opts)
  opts = opts or {}
  return M.by_pattern("Hop 2 char: ", 2, opts)
end

-- Line hint mode.
--
-- Used to tag the beginning of each lines with hints.
M.by_line_start = function(opts)
  opts = opts or {}
  opts.plain_search = false
  opts.oneshot = true
  opts.no_smartcase = true
  return M.by_searching('^', opts)
end

-- Line hint mode skipping leading whitespace.
--
-- Used to tag the beginning of each lines with hints.
M.by_line_start_skip_whitespace = function(opts)
  opts = opts or {}
  opts.plain_search = false
  opts.oneshot = true
  opts.no_smartcase = true
  M.by_searching([[^\s*\zs\($\|\S\)]], opts)
end

-- Turn a table representing a hint into a string.
local function tbl_to_str(hint)
  local s = ''

  for i = 1, #hint do
    s = s .. hint[i]
  end

  return s
end

-- Manhattan distance with column and row, weighted on x so that results are more packed on y.
local function manh_dist(a, b, x_bias)
  local bias = x_bias or 10
  return bias * math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
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
        line = line_nr;
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

-- Reduce a hint.
--
-- This function will remove hints not starting with the input key and will reduce the other ones
-- with one level.
function M.reduce_hint(hint, key)
  local snd_idx = vim.fn.byteidx(hint, 1)
  if hint:sub(1, snd_idx) == key then
    hint = hint:sub(snd_idx + 1)
  end

  if hint == '' then
    hint = nil
  end

  return hint
end

-- Reduce all hints and return the one fully reduced, if any.
function M.reduce_hints(hints, key)
  local output = {}

  for _, h in pairs(hints) do
    local prev_hint = h.hint
    h.hint = M.reduce_hint(h.hint, key)

    if h.hint == nil then
      return h
    elseif h.hint ~= prev_hint then
      output[#output + 1] = h
    end
  end

  return nil, output
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
    hint.handle = {w = hs.hwin, b = hbuf}
    hint.dist = manh_dist(hs.cursor_pos, { hint.line, hint.col });
    hint.wdist = window_dist;
    hint_list[#hint_list+1] = hint
  end
end

function M.create_hint_list_by_scanning_lines(re, hint_states, oneshot)
  -- extract all the words currently visible on screen; the hints variable contains the list
  -- of words as a pair of { line, column } for each word on a given line and indirect_words is a
  -- simple list containing { line, word_index, distance_to_cursor } that is sorted by distance to
  -- cursor, allowing to zip this list with the hints and distribute the hints
  local hints = {}

  local winpos = vim.api.nvim_win_get_position(hint_states[1][1].hwin)
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

function M.assign_character_targets(hint_list, opts)
  local dist_comparison_inner = function(a, b)
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
  local dist_comparison = dist_comparison_inner
  if opts.reverse_distribution then
    dist_comparison = function (a, b) return not dist_comparison_inner(a, b) end
  end

  table.sort(hint_list, dist_comparison)

  local perms = perm.permutations(opts.keys, #hint_list, opts)
  for i = 1, #hint_list do
    hint_list[i].hint = tbl_to_str(perms[i])
  end
end

return M

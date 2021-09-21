local perm = require'hop.perm'
local constants = require'hop.constants'

local M = {}

-- I hate Lua.
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, vim.fn.byteidx(s, 1))
  return f:upper() == f
end

-- Hint modes follow.
-- a hint mode should define a get_hint_list function that returns a list of {line, col} positions for hop targets.

-- Used to hint result of a search.
function M.by_searching(pat, plain_search, oneshot)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end
  local re = vim.regex(pat)
  return {
    oneshot = oneshot,
    match = function(s)
      return re:match_str(s)
    end,

    get_hint_list = function(self, hint_states, opts)
      return M.create_hint_list_by_scanning_lines(self, hint_states, opts)
    end
  }
end

-- Wrapper over M.by_searching to add support for case sensitivity.
function M.by_case_searching(pat, plain_search, opts)
  local ori = pat
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end

  -- append dict pattern for each char in `pat`
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

  if vim.o.smartcase then
    if not starts_with_uppercase(ori) then
      pat = '\\c' .. pat
    end
  elseif opts.case_insensitive then
    pat = '\\c' .. pat
  end

  local re = vim.regex(pat)
  return {
    oneshot = false,
    match = function(s)
      return re:match_str(s)
    end,
    get_hint_list = function(self, hint_states, hint_opts)
      return M.create_hint_list_by_scanning_lines(self, hint_states, hint_opts)
    end
  }
end

-- Word hint mode.
--
-- Used to tag words with hints, its behaviour depends on the
-- iskeyword value.
-- M.by_word_start = M.by_searching('\\<\\k\\+')
M.by_word_start = M.by_searching('\\k\\+')

-- Line hint mode.
--
-- Used to tag the beginning of each lines with hints.
M.by_line_start = M.by_searching('^', false, true)

-- Line hint mode skipping leading whitespace.
--
-- Used to tag the beginning of each lines with hints.
M.by_line_start_skip_whitespace = M.by_searching([[^\s*\zs\($\|\S\)]], false, true)

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
-- The direction_mode argument allows to start / end hint creation after or before the cursor position
--
-- This function returns the list of hints
function M.mark_hints_line(hint_mode, line_nr, line, col_offset, direction_mode)
  local hints = {}
  local shifted_line = line

  -- if no text at line, we can only jump to col=1 when col_offset=0 and hint mode can match empty text
  if type(shifted_line) == "number" then
    if (shifted_line == constants.HintLineException.EMPTY_LINE) and
       (col_offset == 0) and
       (hint_mode.match('')) ~= nil then
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
  if direction_mode ~= nil then
    if direction_mode.direction == constants.HintDirection.AFTER_CURSOR then
      -- we want to change the start offset so that we ignore everything before the cursor
      shifted_line = shifted_line:sub(direction_mode.cursor_col - col_offset)
      col_bias = direction_mode.cursor_col - 1
    elseif direction_mode.direction == constants.HintDirection.BEFORE_CURSOR then
      -- we want to change the end
      shifted_line = shifted_line:sub(1, direction_mode.cursor_col - col_offset + 1)
    end
  end

  local col = 1
  while true do
    local s = shifted_line:sub(col)
    local b, e = hint_mode.match(s)

    if b == nil then
      break
    end

    hints[#hints + 1] = {
      line = line_nr;
      col = col_bias + col + b;
      col_end = col_bias + col + e;
    }

    if hint_mode.oneshot then
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
  hint_mode,
  hbuf,
  hs,
  direction_mode,
  window_dist
)
  local hints = M.mark_hints_line(hint_mode, hs.lnums[i], hs.lines[i], hs.lcols[i], direction_mode)
  for _, hint in pairs(hints) do
    hint.handle = {w = hs.hwin, b = hbuf}
    hint.dist = manh_dist(hs.cursor_pos, { hint.line, hint.col });
    hint.wdist = window_dist;
    hint_list[#hint_list+1] = hint
  end
end

function M.create_hint_list_by_scanning_lines(hint_mode, hint_states, opts)
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

      -- in the case of a direction, we want to treat the first or last line (according to the direction) differently
      if opts.direction == constants.HintDirection.AFTER_CURSOR then
        -- the first line is to be checked first
        create_hints_for_line(1, hints, hint_mode, hbuf, hs, hs.dir_mode, window_dist)
        for i = 2, #hs.lines do
          create_hints_for_line(i, hints, hint_mode, hbuf, hs, nil, window_dist)
        end
      elseif opts.direction == constants.HintDirection.BEFORE_CURSOR then
        -- the last line is to be checked last
        for i = 1, #hs.lines - 1 do
          create_hints_for_line(i, hints, hint_mode, hbuf, hs, nil, window_dist)
        end
        create_hints_for_line(#hs.lines, hints, hint_mode, hbuf, hs, hs.dir_mode, window_dist)
      else
        for i = 1, #hs.lines do
          create_hints_for_line(i, hints, hint_mode, hbuf, hs, nil, window_dist)
        end
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

function M.set_hint_extmarks(hl_ns, hints)
  for _, h in pairs(hints) do
    local hbuf = h.handle.b
    if not vim.api.nvim_buf_is_valid(hbuf) then
      goto __NEXT_HH
    end

    if vim.fn.strdisplaywidth(h.hint) == 1 then
      vim.api.nvim_buf_set_extmark(
        hbuf,
        hl_ns,
        h.line, h.col - 1,
        {
          virt_text = { { h.hint, "HopNextKey" } };
          virt_text_pos = 'overlay'
        })
    else
      -- get the byte index of the second hint so that we can slice it correctly
      local snd_idx = vim.fn.byteidx(h.hint, 1)
      vim.api.nvim_buf_set_extmark(
        hbuf,
        hl_ns,
        h.line, h.col - 1,
        {
          virt_text = { { h.hint:sub(1, snd_idx), "HopNextKey1" }, { h.hint:sub(snd_idx + 1), "HopNextKey2" } };
          virt_text_pos = 'overlay'
        })
    end

    ::__NEXT_HH::
  end
end

return M

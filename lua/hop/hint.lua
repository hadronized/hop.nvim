local perm = require'hop.perm'

local M = {}

M.HintDirection = {
  BEFORE_CURSOR = 1,
  AFTER_CURSOR = 2,
}

-- I hate Lua.
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, vim.fn.byteidx(s, 1))
  return f:upper() == f
end

-- Regex hint mode.
--
-- Used to hint result of a search.
function M.by_searching(pat, plain_search)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end
  return {
    oneshot = false,
    match = function(s)
      return vim.regex(pat):match_str(s)
    end
  }
end

-- Wrapper over M.by_searching to add support for case sensitivity.
function M.by_case_searching(pat, plain_search, opts)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end

  if vim.o.smartcase then
    if not starts_with_uppercase(pat) then
      pat = '\\c' .. pat
    end
  elseif opts.case_insensitive then
    pat = '\\c' .. pat
  end

  return {
    oneshot = false,
    match = function(s)
      return vim.regex(pat):match_str(s)
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
M.by_line_start = {
  oneshot = true,
  match = function(_)
    return 0, 1, false
  end
}

-- Line hint mode skipping leading whitespace.
--
-- Used to tag the beginning of each lines with hints.
function M.by_line_start_skip_whitespace()
  pat = vim.regex("\\S")
  return {
    oneshot = true,
    match = function(s)
      return pat:match_str(s)
    end
  }
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
-- The direction_mode argument allows to start / end hint creation after or before the cursor position
--
-- This function returns the list of hints as well as the length of the line in the form of table:
--
--   { hints, length }
function M.mark_hints_line(hint_mode, line_nr, line, col_offset, win_width, direction_mode)
  local hints = {}
  local end_index = nil

  if win_width ~= nil then
    end_index = col_offset + win_width
  else
    end_index = vim.fn.strdisplaywidth(line)
  end

  local shifted_line = line:sub(1 + col_offset, vim.fn.byteidx(line, end_index))

  -- modify the shifted line to take the direction mode into account, if any
  local col_bias = 0
  if direction_mode ~= nil then
    local col = vim.fn.byteidx(line, direction_mode.cursor_col + 1)
    if direction_mode.direction == M.HintDirection.AFTER_CURSOR then
      -- we want to change the start offset so that we ignore everything before the cursor
      shifted_line = shifted_line:sub(col - col_offset)
      col_bias = col - 1
    elseif direction_mode.direction == M.HintDirection.BEFORE_CURSOR then
      -- we want to change the end
      shifted_line = shifted_line:sub(1, col - col_offset)
    end
  end

  local col = 1
  while true do
    local s = shifted_line:sub(col)
    local b, e = hint_mode.match(s)

    if b == nil or (b == 0 and e == 0) then
      break
    end

    local colb = col + b
    hints[#hints + 1] = {
      line = line_nr;
      col = math.max(1, colb + col_offset + col_bias);
    }

    if hint_mode.oneshot then
      break
    else
      col = col + e
    end
  end

  return {
    hints = hints;
    length = vim.fn.strdisplaywidth(shifted_line)
  }
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
function M.reduce_hints_lines(per_line_hints, key)
  local output = {}
  local update_count = 0

  for _, hints in pairs(per_line_hints) do
    local next_hints = {}

    for _, h in pairs(hints.hints) do
      local prev_hint = h.hint
      h.hint = M.reduce_hint(h.hint, key)

      if h.hint == nil then
        return h
      elseif h.hint ~= prev_hint then
        next_hints[#next_hints + 1] = h
        update_count = update_count + 1
      end
    end

    output[#output + 1] = { hints = next_hints; length = hints.length }
  end

  return nil, output, update_count
end

-- Create hints for a given indexed line.
--
-- This function is used in M.create_hints to apply the hints to all the visible lines in the buffer. The need for such
-- a specialized function is made real because of the possibility to have variations of hinting functions that will also
-- work in a given direction, requiring a more granular control at the line level.
local function create_hints_for_line(
  i,
  hints,
  indirect_hints,
  hint_counts,
  hint_mode,
  win_width,
  cursor_pos,
  col_offset,
  top_line,
  direction_mode,
  lines
)
  local line_hints = M.mark_hints_line(hint_mode, top_line + i - 1, lines[i], col_offset, win_width, direction_mode)
  hints[i] = line_hints

  hint_counts = hint_counts + #line_hints.hints

  for j = 1, #line_hints.hints do
    local hint = line_hints.hints[j]
    indirect_hints[#indirect_hints + 1] = { i = i; j = j; dist = manh_dist(cursor_pos, { hint.line, hint.col }) }
  end

  return hint_counts
end

function M.create_hints(hint_mode, win_width, cursor_pos, col_offset, top_line, lines, direction, opts)
  -- extract all the words currently visible on screen; the hints variable contains the list
  -- of words as a pair of { line, column } for each word on a given line and indirect_words is a
  -- simple list containing { line, word_index, distance_to_cursor } that is sorted by distance to
  -- cursor, allowing to zip this list with the hints and distribute the hints
  local hints = {}
  local indirect_hints = {}
  local hint_counts = 0

  -- in the case of a direction, we want to treat the first or last line (according to the direction) differently
  if direction == M.HintDirection.AFTER_CURSOR then
    -- the first line is to be checked first
    hint_counts = create_hints_for_line(
      1,
      hints,
      indirect_hints,
      hint_counts,
      hint_mode,
      win_width,
      cursor_pos,
      col_offset,
      top_line,
      { cursor_col = cursor_pos[2], direction = direction },
      lines
    )

    for i = 2, #lines do
      hint_counts = create_hints_for_line(
        i,
        hints,
        indirect_hints,
        hint_counts,
        hint_mode,
        win_width,
        cursor_pos,
        col_offset,
        top_line,
        nil,
        lines
      )
    end
  elseif direction == M.HintDirection.BEFORE_CURSOR then
    -- the last line is to be checked last
    for i = 1, #lines - 1 do
      hint_counts = create_hints_for_line(
        i,
        hints,
        indirect_hints,
        hint_counts,
        hint_mode,
        win_width,
        cursor_pos,
        col_offset,
        top_line,
        nil,
        lines
      )
    end

    hint_counts = create_hints_for_line(
      #lines,
      hints,
      indirect_hints,
      hint_counts,
      hint_mode,
      win_width,
      cursor_pos,
      col_offset,
      top_line,
      { cursor_col = cursor_pos[2], direction = direction },
      lines
    )
  else
    for i = 1, #lines do
      hint_counts = create_hints_for_line(
        i,
        hints,
        indirect_hints,
        hint_counts,
        hint_mode,
        win_width,
        cursor_pos,
        col_offset,
        top_line,
        nil,
        lines
      )
    end
  end

  local dist_comparison = nil
  if opts.reverse_distribution then
    dist_comparison = function (a, b) return a.dist > b.dist end
  else
    dist_comparison = function (a, b) return a.dist < b.dist end
  end

  table.sort(indirect_hints, dist_comparison)

  -- generate permutations and update the lines with hints
  local perms = perm.permutations(opts.keys, #indirect_hints, opts)
  for i, indirect in pairs(indirect_hints) do
    hints[indirect.i].hints[indirect.j].hint = tbl_to_str(perms[i])
  end

  return hints,  hint_counts
end

function M.set_hint_extmarks(hl_ns, per_line_hints)
  for _, hints in pairs(per_line_hints) do
    for _, hint in pairs(hints.hints) do
      if vim.fn.strdisplaywidth(hint.hint) == 1 then
        vim.api.nvim_buf_set_extmark(0, hl_ns, hint.line, hint.col - 1, {
          virt_text = { { hint.hint, "HopNextKey" } },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
          priority = 65534 -- 1 priority above the grey highlight
        })
      else
        -- get the byte index of the second hint so that we can slice it correctly
        local snd_idx = vim.fn.byteidx(hint.hint, 1)
        vim.api.nvim_buf_set_extmark(0, hl_ns, hint.line, hint.col - 1, {
          virt_text = { { hint.hint:sub(1, snd_idx), "HopNextKey1" }, { hint.hint:sub(snd_idx + 1), "HopNextKey2" } },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
          priority = 65534 -- 1 priority above the grey highlight
        })
      end
    end
  end
end

return M

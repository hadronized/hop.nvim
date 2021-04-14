local perm = require'hop.perm'

local M = {}

-- I hate Lua.
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, 1)
  return f:upper() == f
end

-- Regex hint mode.
--
-- Used to hint result of a search.
-- pat: Vim pattern used to find matches on the screen.
-- plain_search: Whether to treat the pattern as a literal or not.
-- direction: Whether to match before the cursor, after the cursor, or
-- anywhere.
-- same_line: Whether the pattern should only be applied to the same line as
-- the cursor.
-- opts: Other options passed to Hop.
function M.by_searching(pat, plain_search, direction, same_line, opts)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end
  return {
    direction = direction,
    same_line = same_line,
    oneshot = false,
    match = function(s)
      return vim.regex(pat):match_str(s)
    end
  }
end

-- Wrapper over M.by_searching to add spport for case sensitivity.
function M.by_case_searching(pat, plain_search, direction, same_line, opts)
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
    direction = direction,
    same_line = same_line,
    oneshot = false,
    match = function(s)
      return vim.regex(pat):match_str(s)
    end
  }
end

-- Word hint mode.
--
-- Used to tag words with hints.
-- M.by_word_start = M.by_searching('\\<\\w\\+')
M.by_word_start = M.by_searching('\\w\\+', 'anywhere', false)

-- Line hint mode.
--
-- Used to tag the beginning of each lines with ihnts.
M.by_line_start = {
  direction = 'anywhere',
  same_line = false,
  oneshot = true,
  match = function(_)
    return 0, 1, false
  end
}

-- Like the above, except it keeps the cursor on its current column.
function M.by_line_current(direction)
  return {
    direction = direction,
    same_line = false,
    oneshot = true,
    match = function(s, cursor_pos)
      if s:len() == 0 then
        line_max = s:len()
      else
        line_max = s:len() - 1
      end
      start = math.min(cursor_pos[2], line_max)
      return start, start+1
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
-- contains three fields giving the line, hint column and real column of the hint:
--
--   { line, col }
--
-- The input line_nr is the line number of the line currently being marked.
--
-- This function returns the list of hints as well as the length of the line in the form of table:
--
--   { hints, length }
function M.mark_hints_line(hint_mode, line_nr, line, col_offset, win_width, cursor_pos)
  local hints = {}
  local end_index = nil

  if win_width ~= nil then
    end_index = col_offset + win_width
  else
    end_index = vim.fn.strdisplaywidth(line)
  end

  local shifted_line = line:sub(1 + col_offset, end_index)

  local col = 1


  while not is_invalid do
    local s = shifted_line:sub(col)
    local b, e = hint_mode.match(s, cursor_pos)

    if b == nil or (b == 0 and e == 0) then
      break
    end

    local colb = col + b

    local is_current_line = line_nr + 1 == cursor_pos[1]
    local correct_side_after = hint_mode.direction ~= 'after_cursor' or colb - 1 > cursor_pos[2]
    local correct_side_before = hint_mode.direction ~= 'before_cursor' or colb - 1 < cursor_pos[2]
    if not is_current_line or (correct_side_before and correct_side_after) then
      hints[#hints + 1] = {
        line = line_nr;
        col = colb + col_offset;
      }
    end

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
  if hint:sub(1, 1) == key then
    hint = hint:sub(2)
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

function M.create_hints(hint_mode, win_width, cursor_pos, col_offset, top_line, lines, opts)
  -- extract all the words currently visible on screen; the hints variable contains the list
  -- of words as a pair of { line, column } for each word on a given line and indirect_words is a
  -- simple list containing { line, word_index, distance_to_cursor } that is sorted by distance to
  -- cursor, allowing to zip this list with the hints and distribute the hints
  local hints = {}
  local indirect_hints = {}
  local hint_counts = 0
  for i = 1, #lines do

    local line_nr = top_line + i - 1

    -- A line is too early if it's before the cursor and the motion only
    -- operates on lines after the cursor.
    local line_too_early = hint_mode.direction == 'after_cursor' and line_nr + 1 < cursor_pos[1]
    -- A line is too late if it's after the cursor and the motion only
    -- operates on lines before the cursor.
    local line_too_late = hint_mode.direction == 'before_cursor' and line_nr + 1 > cursor_pos[1]
    -- A line is invalid if it's not on the same line as the cursor and the
    -- motion only operates on the current line.
    local line_not_exact = line_nr + 1 ~= cursor_pos[1] and hint_mode.same_line
    -- A oneshot motion moves between lines so there's no reason to include the
    -- current line in the motion.
    local oneshot_excludes_current = line_nr + 1 == cursor_pos[1] and hint_mode.oneshot
    -- If any of the above bools are true, the line is invalid and shouldn't be hinted.
    local is_invalid = line_too_early or line_too_late or line_not_exact or oneshot_excludes_current

    if not is_invalid then
      local line_hints = M.mark_hints_line(hint_mode, line_nr, lines[i], col_offset, win_width, cursor_pos)
      hints[i] = line_hints

      hint_counts = hint_counts + #line_hints.hints
    else
      hints[i] = {
        hints = {};
        length = 0
      }
    end

    for j = 1, #hints[i].hints do
      local hint = hints[i].hints[j]
      indirect_hints[#indirect_hints + 1] = { i = i; j = j; dist = manh_dist(cursor_pos, { hint.line, hint.col }) }
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
      if #hint.hint == 1 then
        vim.api.nvim_buf_set_extmark(0, hl_ns, hint.line, hint.col - 1, { virt_text = { { hint.hint, "HopNextKey"} }; virt_text_pos = 'overlay' })
      else
        vim.api.nvim_buf_set_extmark(0, hl_ns, hint.line, hint.col - 1, { virt_text = { { hint.hint:sub(1, 1), "HopNextKey1"}, { hint.hint:sub(2), "HopNextKey2" } }; virt_text_pos = 'overlay' })
      end
    end
  end
end

return M

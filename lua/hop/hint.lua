local defaults = require'hop.defaults'
local perm = require'hop.perm'

local M = {}

-- Small utility functions for alignments / filling.
local function next_mul(x, m)
  return x + m - x % m
end

-- Word hint mode.
--
-- Used to tag words with hints.
M.by_word_start = vim.regex('\\<\\w\\+')

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
--   { line, col, real_col }
--
-- The input line_nr is the line number of the line currently being marked.
--
-- This function returns the list of hints as well as the length of the line in the form of table:
--
--   { hints, length }
function M.mark_hints_line(hint_mode, line_nr, line, col_offset, buf_width)
  local hints = {}
  local end_index = nil

  if buf_width ~= nil then
    end_index = col_offset + buf_width
  else
    end_index = vim.fn.strdisplaywidth(line)
  end

  local shifted_line = line:sub(1 + col_offset, end_index)

  local col = 1
  while true do
    local s = shifted_line:sub(col)
    local b, e = hint_mode:match_str(s)

    if b == nil then
      break
    end

    local colb = col + b
    hints[#hints + 1] = {
      line = line_nr;
      col = vim.str_utfindex(shifted_line, colb);
      real_col = colb + col_offset
    }

    col = col + e
  end

  return {
    hints = hints;
    length = vim.fn.strdisplaywidth(line)
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

function M.create_hints(hint_mode, buf_width, buf_height, cursor_pos, col_offset, lines, opts)
  local keys = opts and opts.keys or defaults.keys
  local reverse_distribution = opts and opts.reverse_distribution or defaults.reverse_distribution

  -- extract all the words currently visible on screen; the hints variable contains the list
  -- of words as a pair of { line, column } for each word on a given line and indirect_words is a
  -- simple list containing { line, word_index, distance_to_cursor } that is sorted by distance to
  -- cursor, allowing to zip this list with the hints and distribute the hints
  local hints = {}
  local indirect_hints = {}
  for i = 1, buf_height do
    local line_hints = M.mark_hints_line(hint_mode, i, lines[i], col_offset, buf_width)
    hints[i] = line_hints

    for j = 1, #line_hints.hints do
      local hint = line_hints.hints[j]
      indirect_hints[#indirect_hints + 1] = { i = i; j = j; dist = manh_dist(cursor_pos, { hint.line, hint.col }) }
    end
  end

  local dist_comparison = nil
  if reverse_distribution then
    dist_comparison = function (a, b) return a.dist > b.dist end
  else
    dist_comparison = function (a, b) return a.dist < b.dist end
  end

  table.sort(indirect_hints, dist_comparison)

  -- generate permutations and update the lines with hints
  local perms = perm.permutations(keys, #indirect_hints, opts)
  for i, indirect in pairs(indirect_hints) do
    hints[indirect.i].hints[indirect.j].hint = tbl_to_str(perms[i])
  end

  return hints
end

-- Create the lines for the hint buffer.
--
-- If a hint is too close to another one, it will not be displayed entirely. For instance, imagine the following text
-- to hint by word:
--
--   a b
--
-- If a is associated with x and b is associated with y, the hint buffer will look like this:
--
--   x y
--
-- If a is associated with xw and b is associated with xz, the hint buffer will look like this:
--
--   xwxz
--
-- However, if a is now associated with xwp and b is associated with xwq, the hint buffer will look like this:
--
--   xwxw
--
-- If the user reduces hints by typing x, this last buffer will get reduced to:
--
--   wpwq
--
-- If the user reduces once again by typing w:
--
--   p q
function M.create_buffer_lines(win_width, win_height, per_line_hints)
  local lines = {}
  for line = 1, win_height do
    local col = 1
    local content = ''
    local line_hints = per_line_hints[line]

    if #line_hints.hints > 0 then
      for i = 1, #line_hints.hints - 1 do
        local hint = line_hints.hints[i]

        -- put spaces until we hit the beginning of the hint
        if col < hint.col then
          content = content .. string.rep(' ', hint.col - col)
        end

        -- compute the length the hint will take
        local hint_len = math.min(#hint.hint, line_hints.hints[i + 1].col - hint.col)
        content = content .. hint.hint:sub(1, hint_len)
        col = hint.col + hint_len
      end

      -- the last hint is special as it doesn’t have a next hint; instead, we will use the buf_width as ending column;
      -- because of wrapping lines, we have to compute the right “length”, which is the next multiple buf_width after
      -- hint.col
      local hint = line_hints.hints[#line_hints.hints]
      local logical_width = next_mul(line_hints.length - 1, win_width)
      local hint_len = math.min(#hint.hint, logical_width - hint.col + 1)

      -- put spaces until we hit the beginning of the hint
      if col < hint.col then
        content = content .. string.rep(' ', hint.col - col)
      end

      content = content .. hint.hint:sub(1, hint_len)
      col = hint.col + hint_len
    end

    -- local logical_width = next_mul(col, win_width)
    local logical_width = next_mul(math.max(1, line_hints.length) - 1, win_width)
    -- local logical_width = line_hints.length
    if col < logical_width then
      content = content .. string.rep(' ', logical_width - col + 1)
    end

    lines[line] = content
  end

  return lines
end

return M

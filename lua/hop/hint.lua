local perm = require'hop.perm'

local M = {}

-- Regex hint mode.
--
-- Used to hint result of a search.
function M.by_searching(pat, plain_search, same_line)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end
  return {
    oneshot = false,
    match = function(s, line_nr, cursor_pos)
      if not same_line or line_nr + 1 == cursor_pos[1] then
        return vim.regex(pat):match_str(s)
      else
        return 0, 0
      end
    end
  }
end

-- Wrapper over M.by_searching to add spport for case sensitivity.
function M.by_case_searching(pat, plain_search, opts)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end

  if opts.case_insensitive then
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
-- Used to tag words with hints.
function M.by_word_start(same_line)
  return M.by_searching('\\w\\+', false, same_line)
end

-- This basically reimplements vim's 'w' key movement.
function M.by_w(same_line)
  first_time = true
  return {
    oneshot = false,
    match = function(s, line_nr, cursor_pos)
      if (not same_line and line_nr + 1 >= cursor_pos[1]) or line_nr + 1 == cursor_pos[1] then
        if first_time then
          s = s:sub(cursor_pos[2]+1)
          _,offset = vim.regex('^\\(\\(\\w\\+\\)\\|\\([^[:blank:][:alnum:]_]\\+\\)\\)'):match_str(s)
          offset = (offset or 0)
          s = s:sub(offset+1)
          offset = offset + cursor_pos[2]
        end

        _,i = vim.regex('^\\s*'):match_str(s)
        _,j = vim.regex('^\\s*\\(\\(\\w\\+\\)\\|\\([^[:blank:][:alnum:]_]\\+\\)\\)'):match_str(s)
        j = j or s:len()

        if i == j then
          return 0, 0
        else
          if first_time then
            first_time = false
            return i+offset, j+offset
          else
            return i, j
          end
        end
      else
        return 0, 0
      end
    end
  }
end

function M.by_e(same_line)
  first_time = true
  return {
    oneshot = false,
    match = function(s, line_nr, cursor_pos)
      if (not same_line and line_nr + 1 >= cursor_pos[1]) or line_nr + 1 == cursor_pos[1] then
        if first_time then
          s = s:sub(cursor_pos[2]+2)
          offset = cursor_pos[2] + 1
        end

        _,j = vim.regex('^\\s*\\(\\(\\w\\+\\)\\|\\([^[:blank:][:alnum:]_]\\+\\)\\)'):match_str(s)
        j = j or s:len()

        if s:len() == 0 then
          return 0, 0
        end

        if first_time then
          first_time = false
          return j+offset-1, j+offset
        else
          return j-1, j
        end
      else
        return 0, 0
      end
    end
  }
end

function M.by_ge(same_line)
  start = 0
  return {
    oneshot = false,
    match = function(s, line_nr, cursor_pos)
      if (not same_line and line_nr + 1 >= cursor_pos[1]) or line_nr + 1 == cursor_pos[1] then
        if line_nr + 1 == cursor_pos[1] then
          s = s:sub(0, cursor_pos[2] + 1 - start)
          offset = cursor_pos[2] + 1
        end

        _,j = vim.regex('^\\s*\\(\\(\\w\\+\\)\\|\\([^[:blank:][:alnum:]_]\\+\\)\\)'):match_str(s)
        j = j or s:len()

        if j == s:len() then
          return 0, 0
        end

        if line_nr + 1 == cursor_pos[1] then
          start = start + j
        end
        return j-1, j
      else
        return 0, 0
      end
    end
  }
end

function M.by_b(same_line)
  start = 0
  return {
    oneshot = false,
    match = function(s, line_nr, cursor_pos)
      if (not same_line and line_nr + 1 < cursor_pos[1]) or line_nr + 1 == cursor_pos[1] then
        if line_nr + 1 == cursor_pos[1] then
          s = s:sub(0, cursor_pos[2] - start)
        end

        _,i = vim.regex('^\\s*'):match_str(s)
        _,j = vim.regex('^\\s*\\(\\(\\w\\+\\)\\|\\([^[:blank:][:alnum:]_]\\+\\)\\)'):match_str(s)
        j = j or s:len()

        if i == j then
          return 0, 0
        else
          if line_nr + 1 == cursor_pos[1] then
            start = start + j
          end
          return i, j
        end
      else
        return 0, 0
      end
    end
  }
end

function M.by_find(c, only_till)
  first_time = true
  return {
    oneshot = false,
    match = function(s, line_nr, cursor_pos)
      if line_nr + 1 == cursor_pos[1] then
        if first_time then
          if only_till then
            line_start = cursor_pos[2] + 1
          else
            line_start = cursor_pos[2]
          end
          s = s:sub(line_start+2)
        end
        i = s:find('%' .. c)
        if i == nil then
          return nil, nil
        else
          if only_till then
            i = i - 1
          end
          if first_time then
            first_time = false
            return i + line_start, i + 2 + line_start
          else
            return i-1, i+1
          end
        end
      end
    end
  }
end

function M.by_find_back(c, only_till)
  start = 0
  return {
    oneshot = false,
    match = function(s, line_nr, cursor_pos)
      if line_nr + 1 == cursor_pos[1] then
        if only_till then
          line_start = cursor_pos[2] - 1
        else
          line_start = cursor_pos[2]
        end
        s = s:sub(0, line_start - start)
        i = s:find(c)

        if i == nil then
          return nil, nil
        else
          if only_till then
            i = i + 1
          end
          start = start + i
          return i-1, i
        end
      end
    end
  }
end

-- Line hint mode.
--
-- Used to tag the beginning of each lines with ihnts.
M.by_line_start = {
  oneshot = true,
  match = function(_, _, _)
    return 0, 1, false
  end
}

M.by_j = {
  oneshot = true,
  match = function(s, line_nr, cursor_pos)
    if line_nr >= cursor_pos[1] then
      if s:len() == 0 then
        line_max = s:len()
      else
        line_max = s:len() - 1
      end
      start = math.min(cursor_pos[2], line_max)
      return start, start+1
    else
      return 0, 0
    end
  end
}

M.by_k = {
  oneshot = true,
  match = function(s, line_nr, cursor_pos)
    if line_nr + 1 < cursor_pos[1] then
      if s:len() == 0 then
        line_max = s:len()
      else
        line_max = s:len() - 1
      end
      start = math.min(cursor_pos[2], line_max)
      return start, start+1
    else
      return 0, 0
    end
  end
}

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
  while true do
    local s = shifted_line:sub(col)
    local b, e = hint_mode.match(s, line_nr, cursor_pos)

    if b == nil or (b == 0 and e == 0) then
      break
    end

    local colb = col + b
    hints[#hints + 1] = {
      line = line_nr;
      col = colb + col_offset;
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
    local line_hints = M.mark_hints_line(hint_mode, top_line + i - 1, lines[i], col_offset, win_width, cursor_pos)
    hints[i] = line_hints

    hint_counts = hint_counts + #line_hints.hints

    for j = 1, #line_hints.hints do
      local hint = line_hints.hints[j]
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

local perm = require'hop.perm'
local window = require'hop.window'
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
function M.by_searching(pat, plain_search)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end
  return {
    oneshot = false,
    match = function(s)
      return vim.regex(pat):match_str(s)
    end,

    get_hint_list = function(self, opts)
      return M.create_hint_list_by_scanning_lines(self, opts)
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
    end,
    get_hint_list = function(self, hint_opts)
      return M.create_hint_list_by_scanning_lines(self, hint_opts)
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
  end,
  get_hint_list = function(self, hint_opts)
    return M.create_hint_list_by_scanning_lines(self, hint_opts)
  end
}

-- Line hint mode skipping leading whitespace.
--
-- Used to tag the beginning of each lines with hints.
function M.by_line_start_skip_whitespace()
  local pat = vim.regex("\\S")
  return {
    oneshot = true,
    match = function(s)
      return pat:match_str(s)
    end,
    get_hint_list = function(self, hint_opts)
      return M.create_hint_list_by_scanning_lines(self, hint_opts)
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
-- This function returns the list of hints
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
    if direction_mode.direction == constants.HintDirection.AFTER_CURSOR then
      -- we want to change the start offset so that we ignore everything before the cursor
      shifted_line = shifted_line:sub(col - col_offset)
      col_bias = col - 1
    elseif direction_mode.direction == constants.HintDirection.BEFORE_CURSOR then
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

    output[#output + 1] = { hints = next_hints }
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
  hint_list,
  hint_mode,
  context,
  direction_mode,
  lines
)
  local line_hints = M.mark_hints_line(hint_mode, context.top_line + i - 1, lines[i], context.col_offset, context.win_width, direction_mode)
  for _, val in pairs(line_hints) do
    hint_list[#hint_list+1] = val
  end
end

function M.create_hint_list_by_scanning_lines(hint_mode, opts)
  -- extract all the words currently visible on screen; the hints variable contains the list
  -- of words as a pair of { line, column } for each word on a given line and indirect_words is a
  -- simple list containing { line, word_index, distance_to_cursor } that is sorted by distance to
  -- cursor, allowing to zip this list with the hints and distribute the hints
  local context = window.get_window_context(opts.direction)
  local lines = vim.api.nvim_buf_get_lines(0, context.top_line, context.bot_line + 1, false)
  local hint_list = {}

  -- in the case of a direction, we want to treat the first or last line (according to the direction) differently
  if opts.direction == constants.HintDirection.AFTER_CURSOR then
    -- the first line is to be checked first
    create_hints_for_line(
      1,
      hint_list,
      hint_mode,
      context,
      { cursor_col = context.cursor_pos[2], direction = opts.direction },
      lines
    )

    for i = 2, #lines do
      create_hints_for_line(
        i,
        hint_list,
        hint_mode,
        context,
        nil,
        lines
      )
    end
  elseif opts.direction == constants.HintDirection.BEFORE_CURSOR then
    -- the last line is to be checked last
    for i = 1, #lines - 1 do
      create_hints_for_line(
        i,
        hint_list,
        hint_mode,
        context,
        nil,
        lines
      )
    end

    create_hints_for_line(
      #lines,
      hint_list,
      hint_mode,
      context,
      { cursor_col = context.cursor_pos[2], direction = opts.direction },
      lines
    )
  else
    for i = 1, #lines do
      create_hints_for_line(
        i,
        hint_list,
        hint_mode,
        context,
        nil,
        lines
      )
    end
  end

  return hint_list
end

function M.assign_character_targets(context, hint_list, opts)
  local dist_comparison = nil

  for _, hint in pairs(hint_list) do
    hint.dist = manh_dist(context.cursor_pos, {hint.line, hint.col})
  end

  if opts.reverse_distribution then
    dist_comparison = function (a, b) return a.dist > b.dist end
  else
    dist_comparison = function (a, b) return a.dist < b.dist end
  end

  table.sort(hint_list, dist_comparison)

  local perms = perm.permutations(opts.keys, #hint_list, opts)
  for i = 1, #hint_list do
    hint_list[i].hint = tbl_to_str(perms[i])
  end
end

function M.set_hint_extmarks(hl_ns, per_line_hints)
  for _, hints in pairs(per_line_hints) do
    for _, hint in pairs(hints.hints) do
      if vim.fn.strdisplaywidth(hint.hint) == 1 then
        vim.api.nvim_buf_set_extmark(0, hl_ns, hint.line, hint.col - 1, { virt_text = { { hint.hint, "HopNextKey" } }; virt_text_pos = 'overlay' })
      else
        -- get the byte index of the second hint so that we can slice it correctly
        local snd_idx = vim.fn.byteidx(hint.hint, 1)
        vim.api.nvim_buf_set_extmark(0, hl_ns, hint.line, hint.col - 1, { virt_text = { { hint.hint:sub(1, snd_idx), "HopNextKey1" }, { hint.hint:sub(snd_idx + 1), "HopNextKey2" } }; virt_text_pos = 'overlay' })
      end
    end
  end
end

return M

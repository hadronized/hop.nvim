-- Jump targets are locations in buffers where users might jump to.

local hint = require'hop.hint'
local window = require'hop.window'

local M = {}

-- Jump targets.
--
-- Jump targets are wrapped in this table and provide the required information so that Hop can associate label and
-- display the hints.
--
-- {
--   jump_targets = {},
--   jump_target_count = 0,
--   indirect_jump_targets = {},
-- }

-- A single jump target.
--
-- A jump target is simply a location in a given buffer. So you can picture a jump target as a triple
-- (line, column, buffer).
--
-- {
--   line = 0,
--   column = 0,
--   buffer = 0,
-- }

-- An indirect jump target.
--
-- This table allows to quickly score and sort jump targets. The `index` field gives the index in the `JumpTargetList`
-- the `score` references.
--
-- {
--   index = 0,
--   score = 0,
-- }

-- Manhattan distance with column and row, weighted on x so that results are more packed on y.
local function manh_dist(a, b, x_bias)
  local bias = x_bias or 10
  return bias * math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
end

-- Mark the current line with jump targets.
--
-- Returns the jump targets as described above.
local function mark_jump_targets_line(regex, line_nr, line, col_offset, win_width, direction_mode)
  local jump_targets = {}
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
    if direction_mode.direction == hint.HintDirection.AFTER_CURSOR then
      -- we want to change the start offset so that we ignore everything before the cursor
      shifted_line = shifted_line:sub(col - col_offset)
      col_bias = col - 1
    elseif direction_mode.direction == hint.HintDirection.BEFORE_CURSOR then
      -- we want to change the end
      shifted_line = shifted_line:sub(1, col - col_offset)
    end
  end

  local col = 1
  while true do
    local s = shifted_line:sub(col)
    local b, e = regex.match(s)

    if b == nil or (b == 0 and e == 0) then
      break
    end

    local colb = col + b
    jump_targets[#jump_targets + 1] = {
      line = line_nr,
      column = math.max(1, colb + col_offset + col_bias),
      buffer = 0,
    }

    if regex.oneshot then
      break
    else
      col = col + e
    end
  end

  return jump_targets
end

-- Create jump targets for a given indexed line.
--
-- This function creates the jump targets for the current (indexed) line and appends them to the input list of jump
-- targets `jump_targets`.
--
-- Indirect jump targets are used later to sort jump targets by score and create hints.
local function create_jump_targets_for_line(
  i,
  jump_targets,
  indirect_jump_targets,
  regex,
  context,
  direction_mode,
  lines
)
  -- first, create the jump targets for the ith line
  local line_jump_targets = mark_jump_targets_line(
    regex,
    context.top_line + i - 1,
    lines[i],
    context.col_offset,
    context.win_width,
    direction_mode
  )

  -- then, append those to the input jump target list and create the indexed jump targets
  for _, jump_target in pairs(line_jump_targets) do
    jump_targets[#jump_targets + 1] = jump_target

    indirect_jump_targets[#indirect_jump_targets + 1] = {
      index = #jump_targets,
      score = manh_dist(context.cursor_pos, { jump_target.line, jump_target.column })
    }
  end
end

-- Create jump targets by scanning lines in the currently visible buffer.
--
-- This function takes a regex argument, which is an object containing a match function that must return the span
-- (inclusive beginning, exclusive end) of the match item, or nil when no more match is possible. This object also
-- contains the `oneshot` field, a boolean stating whether only the first match of a line should be taken into account.
--
-- This function returns the lined jump targets (an array of N lines, where N is the number of currently visible lines).
-- Lines without jump targets are assigned an empty table ({}). For lines with jump targets, a list-table contains the
-- jump targets as pair of { line, col }.
--
-- In addition the jump targets, this function returns the total number of jump targets (i.e. this is the same thing as
-- traversing the lined jump targets and summing the number of jump targets for all lines) as a courtesy, plus «
-- indirect jump targets. » Indirect jump targets are encoded as a flat list-table containing three values: i, for the
-- ith line, j, for the rank of the jump target, and dist, the score distance of the associated jump target. This list
-- is sorted according to that last dist parameter in order to know how to distribute the jump targets over the buffer.
local function create_jump_targets_by_scanning_lines(regex, opts)
  local context = window.get_window_context(opts.direction)
  local lines = vim.api.nvim_buf_get_lines(0, context.top_line, context.bot_line + 1, false)
  local jump_targets = {}
  local indirect_jump_targets = {}

  -- in the case of a direction, we want to treat the first or last line (according to the direction) differently
  if opts.direction == hint.HintDirection.AFTER_CURSOR then
    -- the first line is to be checked first
    create_jump_targets_for_line(
      1,
      jump_targets,
      indirect_jump_targets,
      regex,
      context,
      { cursor_col = context.cursor_pos[2], direction = opts.direction },
      lines
    )

    for i = 2, #lines do
      create_jump_targets_for_line(
        i,
        jump_targets,
        indirect_jump_targets,
        regex,
        context,
        nil,
        lines
      )
    end
  elseif opts.direction == hint.HintDirection.BEFORE_CURSOR then
    -- the last line is to be checked last
    for i = 1, #lines - 1 do
      create_jump_targets_for_line(
        i,
        jump_targets,
        indirect_jump_targets,
        regex,
        context,
        nil,
        lines
      )
    end

    create_jump_targets_for_line(
      #lines,
      jump_targets,
      indirect_jump_targets,
      regex,
      context,
      { cursor_col = context.cursor_pos[2], direction = opts.direction },
      lines
    )
  else
    for i = 1, #lines do
      create_jump_targets_for_line(
        i,
        jump_targets,
        indirect_jump_targets,
        regex,
        context,
        nil,
        lines
      )
    end
  end

  local score_comparison = nil
  if opts.reverse_distribution then
    score_comparison = function (a, b) return a.score > b.score end
  else
    score_comparison = function (a, b) return a.score < b.score end
  end

  table.sort(indirect_jump_targets, score_comparison)

  return jump_targets, indirect_jump_targets
end

-- Jump target generator for buffer-based line regexes.
function M.jump_target_generator_by_scanning_lines(regex)
  return {
    get_jump_targets = function(opts)
      return create_jump_targets_by_scanning_lines(regex, opts)
    end
  }
end

-- Regex modes for the buffer-driven generator.
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, vim.fn.byteidx(s, 1))
  return f:upper() == f
end

-- Regex by searching a pattern.
function M.regex_by_searching(pat, plain_search)
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

-- Wrapper over M.regex_by_searching to add support for case sensitivity.
function M.regex_by_case_searching(pat, plain_search, opts)
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

-- Word regex.
function M.regex_by_word_start()
  return M.regex_by_searching('\\k\\+')
end

-- Line regex.
function M.regex_by_line_start()
  return {
    oneshot = true,
    match = function(_)
      return 0, 1, false
    end
  }
end

-- Line regex skipping finding the first non-whitespace character on each line.
function M.regex_by_line_start_skip_whitespace()
  local pat = vim.regex("\\S")
  return {
    oneshot = true,
    match = function(s)
      return pat:match_str(s)
    end
  }
end

return M
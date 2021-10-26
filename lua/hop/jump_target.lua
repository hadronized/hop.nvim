-- Jump targets are locations in buffers where users might jump to.

local hint = require'hop.hint'
local window = require'hop.window'

local M = {}

-- Manhattan distance with column and row, weighted on x so that results are more packed on y.
local function manh_dist(a, b, x_bias)
  local bias = x_bias or 10
  return bias * math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
end

-- FIXME: determine why we need the length here
-- Mark the current line with jump targets.
--
-- A jump target is a simple { line, col } pair. This function returns { jump_targets, length }, where jump_targets is a
-- list (table) of jump targets as described above and length is the length of the line for which we computed the jump
-- target.
local function mark_jump_targets_line(hint_mode, line_nr, line, col_offset, win_width, direction_mode)
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
    local b, e = hint_mode.match(s)

    if b == nil or (b == 0 and e == 0) then
      break
    end

    local colb = col + b
    jump_targets[#jump_targets + 1] = {
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
    jump_targets = jump_targets;
    length = vim.fn.strdisplaywidth(shifted_line)
  }
end

-- Create jump targets for a given indexed line.
--
-- This function creates the jump targets for the current (indexed) line and appends them to the input list of jump
-- targets `jump_targets`.
--
-- `indirect_jump_targets` is appended a table of three objects: the `i` index, referencing the line of the jump target,
-- the `j` index, referencing the index in the jump targets list for the ith line, and a score called `dist`. That score
-- is currently implemented in terms of a Manhattan distance to the cursor in the buffer (the closer the lower).
--
-- Indirect jump targets are used later to sort jump targets by score and create hints.
local function create_jump_targets_for_line(
  i,
  jump_targets,
  indirect_jump_targets,
  jump_target_counts,
  hint_mode,
  context,
  direction_mode,
  lines
)
  local line_jump_targets = mark_jump_targets_line(
    hint_mode,
    context.top_line + i - 1,
    lines[i], context.col_offset,
    context.win_width, direction_mode
  )
  jump_targets[i] = line_jump_targets
  jump_target_counts = jump_target_counts + #line_jump_targets.jump_targets

  for j = 1, #line_jump_targets.jump_targets do
    local jump_target = line_jump_targets.jump_targets[j]
    indirect_jump_targets[#indirect_jump_targets + 1] = { i = i; j = j; dist = manh_dist(context.cursor_pos, { jump_target.line, jump_target.col }) }
  end

  return jump_target_counts
end

-- Create jump targets by scanning lines in the currently visible buffer.
function M.create_jump_targets_by_scanning_lines(hint_mode, opts)
  local context = window.get_window_context(opts.direction)
  local lines = vim.api.nvim_buf_get_lines(0, context.top_line, context.bot_line + 1, false)
  local jump_targets = {}
  local indirect_jump_targets = {}
  local jump_target_counts = 0

  -- in the case of a direction, we want to treat the first or last line (according to the direction) differently
  if opts.direction == hint.HintDirection.AFTER_CURSOR then
    -- the first line is to be checked first
    jump_target_counts = create_jump_targets_for_line(
      1,
      jump_targets,
      indirect_jump_targets,
      jump_target_counts,
      hint_mode,
      context,
      { cursor_col = context.cursor_pos[2], direction = opts.direction },
      lines
    )

    for i = 2, #lines do
      jump_target_counts = create_jump_targets_for_line(
        i,
        jump_targets,
        indirect_jump_targets,
        jump_target_counts,
        hint_mode,
        context,
        nil,
        lines
      )
    end
  elseif opts.direction == hint.HintDirection.BEFORE_CURSOR then
    -- the last line is to be checked last
    for i = 1, #lines - 1 do
      jump_target_counts = create_jump_targets_for_line(
        i,
        jump_targets,
        indirect_jump_targets,
        jump_target_counts,
        hint_mode,
        context,
        nil,
        lines
      )
    end

    jump_target_counts = create_jump_targets_for_line(
      #lines,
      jump_targets,
      indirect_jump_targets,
      jump_target_counts,
      hint_mode,
      context,
      { cursor_col = context.cursor_pos[2], direction = opts.direction },
      lines
    )
  else
    for i = 1, #lines do
      jump_target_counts = create_jump_targets_for_line(
        i,
        jump_targets,
        indirect_jump_targets,
        jump_target_counts,
        hint_mode,
        context,
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

  table.sort(indirect_jump_targets, dist_comparison)

  return jump_targets, jump_target_counts, indirect_jump_targets
end

return M

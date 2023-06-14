-- Jump targets are locations in buffers where users might jump to. They are wrapped in a table and provide the
-- required information so that Hop can associate label and display the hints.
---@class Locations
---@field jump_targets JumpTarget[]
---@field indirect_jump_targets IndirectJumpTarget[]

-- A single jump target is simply a location in a given buffer.
-- So you can picture a jump target as a triple (line, column, window).
---@class JumpTarget
---@field buffer number
---@field line number
---@field column number
---@field length number
---@field window number

-- Indirect jump targets are encoded as a flat list-table of pairs (index, score). This table allows to quickly score
-- and sort jump targets. The `index` field gives the index in the `jump_targets` list. The `score` is any number. The
-- rule is that the lower the score is, the less prioritized the jump target will be.
---@class IndirectJumpTarget
---@field index number
---@field score number

---@class DirectionMode
---@field direction HintDirection
---@field cursor_col number

---@class JumpContext
---@field buf_handle number
---@field win_handle number
---@field regex Regex
---@field line_context LineContext
---@field col_offset number
---@field cursor_pos any[]
---@field win_width number
---@field direction_mode DirectionMode
---@field hint_position HintPosition

---@class Regex
---@field oneshot boolean
---@field match function
---@field linewise boolean determines if regex considers whole lines

local hint = require('hop.hint')
local window = require('hop.window')

---@class JumpTargetModule
local M = {}

-- Manhattan distance with column and row, weighted on x so that results are more packed on y.
---@param a number[]
---@param b number[]
---@param x_bias? number
---@return number
local function manh_dist(a, b, x_bias)
  local bias = x_bias or 10
  return bias * math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
end

-- Mark the current line with jump targets.
--- @param ctx JumpContext
---@return JumpTarget[]
local function mark_jump_targets_line(ctx)
  ---@type JumpTarget[]
  local jump_targets = {}

  local end_index = vim.fn.strdisplaywidth(ctx.line_context.line)
  if ctx.win_width ~= nil then
    end_index = ctx.col_offset + ctx.win_width
  end

  local shifted_line = ctx.line_context.line:sub(1 + ctx.col_offset, vim.fn.byteidx(ctx.line_context.line, end_index))

  -- modify the shifted line to take the direction mode into account, if any
  -- FIXME: we also need to do that for the cursor
  local col_bias = 0
  if ctx.direction_mode ~= nil then
    local col = vim.fn.byteidx(ctx.line_context.line, ctx.direction_mode.cursor_col + 1)
    if ctx.direction_mode.direction == hint.HintDirection.AFTER_CURSOR then
      -- we want to change the start offset so that we ignore everything before the cursor
      shifted_line = shifted_line:sub(col - ctx.col_offset)
      col_bias = col - 1
    elseif ctx.direction_mode.direction == hint.HintDirection.BEFORE_CURSOR then
      -- we want to change the end
      shifted_line = shifted_line:sub(1, col - ctx.col_offset)
    end
  end

  local col = 1
  while true do
    local s = shifted_line:sub(col)
    local b, e = ctx.regex.match(s, {
      line = ctx.line_context.line_nr,
      column = math.max(1, col + ctx.col_offset + col_bias),
      buffer = ctx.buf_handle,
      window = ctx.win_handle,
    })

    -- match empty lines only in linewise regexes
    if b == nil or ((b == 0 and e == 0) and not ctx.regex.linewise) then
      break
    end
    -- Preview need a length to highlight the matched string. Zero means nothing to highlight.
    local matched_length = e - b
    -- As the make for jump target must be placed at a cell (but some pattern like '^' is
    -- placed between cells), we should make sure e > b
    if b == e then
      e = e + 1
    end

    local colp = col + b
    if ctx.hint_position == hint.HintPosition.MIDDLE then
      colp = col + math.floor((b + e) / 2)
    elseif ctx.hint_position == hint.HintPosition.END then
      colp = col + e - 1
    end
    jump_targets[#jump_targets + 1] = {
      line = ctx.line_context.line_nr,
      column = math.max(1, colp + ctx.col_offset + col_bias),
      length = math.max(0, matched_length),
      buffer = ctx.buf_handle,
      window = ctx.win_handle,
    }

    -- do not search further if regex is oneshot or if there is nothing more to search
    if ctx.regex.oneshot or s == '' then
      break
    end
    col = col + e
  end

  return jump_targets
end

-- Create jump targets for a given indexed line.
-- This function creates the jump targets for the current (indexed) line and appends them to the input list of jump
-- targets `jump_targets`.
---@param ctx JumpContext
---@param locations Locations used later to sort jump targets by score and create hints.
local function create_jump_targets_for_line(ctx, locations)
  -- first, create the jump targets for the ith line
  local line_jump_targets = mark_jump_targets_line(ctx)

  -- then, append those to the input jump target list and create the indexed jump targets
  local win_bias = math.abs(vim.api.nvim_get_current_win() - ctx.win_handle) * 1000
  for _, jump_target in pairs(line_jump_targets) do
    locations.jump_targets[#locations.jump_targets + 1] = jump_target

    locations.indirect_jump_targets[#locations.indirect_jump_targets + 1] = {
      index = #locations.jump_targets,
      score = manh_dist(ctx.cursor_pos, { jump_target.line, jump_target.column }) + win_bias,
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
---@param regex Regex
---@return function
function M.jump_targets_by_scanning_lines(regex)
  return function(opts)
    -- get the window context; this is used to know which part of the visible buffer is to hint
    local all_ctxs = window.get_window_context(opts)

    ---@type Locations
    local Locations = {
      jump_targets = {},
      indirect_jump_targets = {},
    }
    ---@type JumpContext
    local Context = {
      regex = regex,
      hint_position = opts.hint_position,
    }

    -- Iterate all buffers
    for _, bctx in ipairs(all_ctxs) do
      -- Iterate all windows of a same buffer
      Context.buf_handle = bctx.buffer_handle
      for _, wctx in ipairs(bctx.contexts) do
        window.clip_window_context(wctx, opts.direction)

        Context.win_handle = wctx.hwin
        Context.col_offset = wctx.col_offset
        Context.win_width = wctx.win_width
        Context.cursor_pos = wctx.cursor_pos
        -- Get all lines' context
        local lines = window.get_lines_context(bctx.buffer_handle, wctx)
        -- in the case of a direction, we want to treat the first or last line (according to the direction) differently
        if opts.direction == hint.HintDirection.AFTER_CURSOR then
          -- the first line is to be checked first
          if not Context.regex.linewise then
            Context.direction_mode = { cursor_col = wctx.cursor_pos[2], direction = opts.direction }
            Context.line_context = lines[1]
            create_jump_targets_for_line(Context, Locations)
          end

          Context.direction_mode = nil
          for i = 2, #lines do
            Context.line_context = lines[i]
            create_jump_targets_for_line(Context, Locations)
          end
        elseif opts.direction == hint.HintDirection.BEFORE_CURSOR then
          -- the last line is to be checked last
          Context.direction_mode = nil
          for i = 1, #lines - 1 do
            Context.line_context = lines[i]
            create_jump_targets_for_line(Context, Locations)
          end

          if not Context.regex.linewise then
            Context.direction_mode = { cursor_col = wctx.cursor_pos[2], direction = opts.direction }
            Context.line_context = lines[#lines]
            create_jump_targets_for_line(Context, Locations)
          end
        else
          Context.direction_mode = nil
          for i = 1, #lines do
            Context.line_context = lines[i]
            -- do not mark current line in active window
            if
              not (
                Context.regex.linewise
                and Context.line_context.line_nr == vim.api.nvim_win_get_cursor(Context.win_handle)[1] - 1
                and vim.api.nvim_get_current_win() == Context.win_handle
              )
            then
              create_jump_targets_for_line(Context, Locations)
            end
          end
        end
      end
    end

    M.sort_indirect_jump_targets(Locations.indirect_jump_targets, opts)

    return Locations
  end
end

-- Jump target generator for regex applied only on the cursor line.
---@param regex Regex
---@return function
function M.jump_targets_for_current_line(regex)
  return function(opts)
    local context = window.get_window_context(opts)[1].contexts[1]
    local line_n = context.cursor_pos[1]
    local line = vim.api.nvim_buf_get_lines(0, line_n - 1, line_n, false)
    local Locations = {
      jump_targets = {},
      indirect_jump_targets = {},
    }

    create_jump_targets_for_line({
      buf_handle = 0,
      win_handle = 0,
      regex = regex,
      col_offset = context.col_offset,
      win_width = context.win_width,
      cursor_pos = context.cursor_pos,
      direction_mode = { cursor_col = context.cursor_pos[2], direction = opts.direction },
      hint_position = opts.hint_position,
      line_context = { line_nr = line_n - 1, line = line[1] },
    }, Locations)

    M.sort_indirect_jump_targets(Locations.indirect_jump_targets, opts)

    return Locations
  end
end

-- Apply a score function based on the Manhattan distance to indirect jump targets.
---
---@param indirect_jump_targets IndirectJumpTarget[]
---@param opts Options
function M.sort_indirect_jump_targets(indirect_jump_targets, opts)
  local score_comparison = function(a, b)
    return a.score < b.score
  end
  if opts.reverse_distribution then
    score_comparison = function(a, b)
      return a.score > b.score
    end
  end

  table.sort(indirect_jump_targets, score_comparison)
end

-- Regex modes for the buffer-driven generator.
---@param s string
---@return boolean
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, vim.fn.byteidx(s, 1))
  -- if it’s a space, we assume it’s not uppercase, even though Lua doesn’t agree with us; I mean, Lua is horrible, who
  -- would like to argue with that creature, right?
  if f == ' ' then
    return false
  end

  return f:upper() == f
end

-- Regex by searching a pattern.
---@param pat string
---@param plain_search? boolean
---@return Regex
local function regex_by_searching(pat, plain_search)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end

  local regex = vim.regex(pat)

  return {
    oneshot = false,
    match = function(s)
      return regex:match_str(s)
    end,
  }
end

-- Wrapper over M.regex_by_searching to add support for case sensitivity.
---@param pat string
---@param plain_search boolean
---@param opts Options
---@return Regex
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

  local regex = vim.regex(pat)

  return {
    oneshot = false,
    match = function(s)
      return regex:match_str(s)
    end,
  }
end

-- Word regex.
---@return Regex
function M.regex_by_word_start()
  return regex_by_searching('\\k\\+')
end

-- Camel case regex
---@return Regex
function M.regex_by_camel_case()
  local camel = '\\u\\l\\+'
  local acronyms = '\\u\\+\\ze\\u\\l'
  local upper = '\\u\\+'
  local lower = '\\l\\+'
  local rgb = '#\\x\\+\\>'
  local ox = '\\<0[xX]\\x\\+\\>'
  local oo = '\\<0[oO][0-7]\\+\\>'
  local ob = '\\<0[bB][01]\\+\\>'
  local num = '\\d\\+'

  local tab = { camel, acronyms, upper, lower, rgb, ox, oo, ob, num, '\\~', '!', '@', '#', '$' }
  -- regex that matches camel or acronyms or upper ... or num ...
  local patStr = '\\%(\\%(' .. table.concat(tab, '\\)\\|\\%(') .. '\\)\\)'

  local pat = vim.regex(patStr)
  return {
    oneshot = false,
    match = function(s)
      return pat:match_str(s)
    end,
  }
end

-- Line regex.
---@return Regex
function M.by_line_start()
  local c = vim.fn.winsaveview().leftcol

  return {
    oneshot = true,
    linewise = true,
    match = function(s)
      local l = vim.fn.strdisplaywidth(s)
      if c > 0 and l == 0 then
        return nil
      end

      return 0, 1
    end,
  }
end

-- Line regex at cursor position.
---@return Regex
function M.regex_by_vertical()
  local buf = vim.api.nvim_win_get_buf(0)
  local line, col = table.unpack(vim.api.nvim_win_get_cursor(0))
  local regex = vim.regex(string.format('^.\\{0,%d\\}\\(.\\|$\\)', col))
  return {
    oneshot = true,
    linewise = true,
    match = function(s, ctx)
      if ctx.buffer == buf and ctx.line == line - 1 then
        return nil
      end
      return regex:match_str(s)
    end,
  }
end

-- Line regex skipping finding the first non-whitespace character on each line.
---@return Regex
function M.regex_by_line_start_skip_whitespace()
  local regex = vim.regex('\\S')

  return {
    oneshot = true,
    linewise = true,
    match = function(s)
      return regex:match_str(s)
    end,
  }
end

-- Anywhere regex.
---@return Regex
function M.regex_by_anywhere()
  return regex_by_searching('\\v(<.|^$)|(.>|^$)|(\\l)\\zs(\\u)|(_\\zs.)|(#\\zs.)')
end

return M

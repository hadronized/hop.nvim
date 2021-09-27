local util = require"hop.hint_util"
local M = {}

function M.by_pattern(prompt, max_chars, opts)
  opts = opts or {}

  local strategy = {
    get_hint_list = function()
      local hint_states = util.create_hint_states(opts.multi_windows, opts.direction)
      return util.get_pattern(prompt, max_chars, opts.preview and opts, hint_states), {grey_out = util.get_grey_out(hint_states)}
    end,
    comparator = util.win_cursor_dist_comparator,
    callback = util.callbacks.win_goto
  }
  return strategy
end

-- Used to hint result of a search.
function M.by_searching(pat, opts)
  opts = opts or {}

  local re = util.format_pat(pat, opts)

  local strategy = {
    get_hint_list = function()
      local hint_states = util.create_hint_states(opts.multi_windows, opts.direction)
      return util.create_hint_list_by_scanning_lines(re, hint_states, opts.oneshot),
        {grey_out = util.get_grey_out(hint_states)}
    end,
    comparator = util.comparators.win_cursor_dist_comparator,
    callback = util.callbacks.win_goto
  }
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
  return M.by_searching([[^\s*\zs\($\|\S\)]], opts)
end

return M

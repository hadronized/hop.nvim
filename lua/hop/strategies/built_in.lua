local util = require"hop.hint_util"
local M = {}

---@param prompt string @prompt to display when querying pattern
---@param max_chars number @maximum number of chars to input before automatically hinting
function M.by_pattern(prompt, max_chars, opts)
  opts = opts or {}

  ---@type Strategy
  local strategy = {
    get_hint_list = function()
      local windows = opts.multi_windows and vim.api.nvim_tabpage_list_wins(0) or {vim.api.nvim_get_current_win()}
      local views_data = util.create_views_data(windows, opts.direction)
      return util.get_pattern(prompt, max_chars, opts.preview, opts.fmt_opts, views_data),
        {grey_out = util.get_grey_out(views_data)}
    end,
    comparator = util.win_cursor_dist_comparator,
    callback = util.callbacks.win_goto
  }
  return strategy
end

-- Used to hint result of a search.
function M.by_searching(pat, opts)
  opts = opts or {}

  local re = util.format_pat(pat, opts.fmt_opts)

  local strategy = {
    get_hint_list = function()
      local windows = opts.multi_windows and vim.api.nvim_tabpage_list_wins(0) or {vim.api.nvim_get_current_win()}
      local views_data = util.create_views_data(windows, opts.direction)
      return util.create_hint_list_by_scanning_lines(re, views_data, opts.oneshot),
        {grey_out = util.get_grey_out(views_data)}
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
  opts.fmt_opts = opts.fmt_opts or {}
  opts.fmt_opts.no_smartcase = true
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
  opts.oneshot = true
  opts.fmt_opts = opts.fmt_opts or {}
  opts.fmt_opts.plain_search = false
  opts.fmt_opts.no_smartcase = true
  return M.by_searching('^', opts)
end

-- Line hint mode skipping leading whitespace.
--
-- Used to tag the beginning of each lines with hints.
M.by_line_start_skip_whitespace = function(opts)
  opts = opts or {}
  opts.oneshot = true
  opts.fmt_opts = opts.fmt_opts or {}
  opts.fmt_opts.plain_search = false
  opts.fmt_opts.no_smartcase = true
  return M.by_searching([[^\s*\zs\($\|\S\)]], opts)
end

return M

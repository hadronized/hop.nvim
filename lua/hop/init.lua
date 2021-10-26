local defaults = require'hop.defaults'
local hint = require'hop.hint'
local jump_target = require'hop.jump_target'
local prio = require'hop.priority'
local window = require'hop.window'

local M = {}

-- Allows to override global options with user local overrides.
local function get_command_opts(local_opts)
  -- In case, local opts are defined, chain opts lookup: [user_local] -> [user_global] -> [default]
  return local_opts and setmetatable(local_opts, {__index = M.opts}) or M.opts
end

-- Display error messages.
local function eprintln(msg, teasing)
  if teasing then
    vim.api.nvim_echo({{msg, 'Error'}}, true, {})
  end
end

-- A hack to prevent #57 by deleting twice the namespace (it’s super weird).
local function clear_namespace(buf_handle, hl_ns)
  vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, 0, -1)
end

-- Grey everything out to prepare the Hop session.
--
-- - hl_ns is the highlight namespace.
-- - top_line is the top line in the buffer to start highlighting at
-- - bottom_line is the bottom line in the buffer to stop highlighting at
local function grey_things_out(buf_handle, hl_ns, top_line, bottom_line, direction_mode)
  if direction_mode ~= nil then
    if direction_mode.direction == hint.HintDirection.AFTER_CURSOR then
      vim.api.nvim_buf_set_extmark(buf_handle, hl_ns, top_line, direction_mode.cursor_col, {
        end_line = bottom_line + 1,
        hl_group = 'HopUnmatched',
        hl_eol = true,
        priority = prio.DIM_PRIO
      })
    elseif direction_mode.direction == hint.HintDirection.BEFORE_CURSOR then
      vim.api.nvim_buf_set_extmark(buf_handle, hl_ns, top_line, 0, {
        end_line = bottom_line,
        end_col = direction_mode.cursor_col,
        hl_group = 'HopUnmatched',
        hl_eol = true,
        priority = prio.DIM_PRIO
      })
    end
  else
    vim.api.nvim_buf_set_extmark(buf_handle, hl_ns, top_line, 0, {
      end_line = bottom_line + 1,
      hl_group = 'HopUnmatched',
      hl_eol = true,
      priority = prio.DIM_PRIO
    })
  end
end

-- Add the virtual cursor, taking care to handle the cases where:
-- - the virtualedit option is being used and the cursor is in a
--   tab character or past the end of the line
-- - the current line is empty
-- - there are multibyte characters on the line
local function add_virt_cur(ns)
  local cur_info = vim.fn.getcurpos()
  local cur_row = cur_info[2] - 1
  local cur_col = cur_info[3] - 1 -- this gives cursor column location, in bytes
  local cur_offset = cur_info[4]
  local virt_col = cur_info[5] - 1
  local cur_line = vim.api.nvim_get_current_line()

  -- first check to see if cursor is in a tab char or past end of line
  if cur_offset ~= 0 then
    vim.api.nvim_buf_set_extmark(0, ns, cur_row, cur_col, {
      virt_text = {{'█', 'Normal'}},
      virt_text_win_col = virt_col,
      priority = prio.CURSOR_PRIO
    })
  -- otherwise check to see if cursor is at end of line or on empty line
  elseif #cur_line == cur_col then
    vim.api.nvim_buf_set_extmark(0, ns, cur_row, cur_col, {
      virt_text = {{'█', 'Normal'}},
      virt_text_pos = 'overlay',
      priority = prio.CURSOR_PRIO
    })
  else
    vim.api.nvim_buf_set_extmark(0, ns, cur_row, cur_col, {
      -- end_col must be column of next character, in bytes
      end_col = vim.fn.byteidx(cur_line, vim.fn.charidx(cur_line, cur_col) + 1),
      hl_group = 'HopCursor',
      priority = prio.CURSOR_PRIO
    })
  end
end

-- TODO: move as part of a « buffer line » mode
-- Hint the whole visible part of the buffer.
--
-- The 'hint_mode' argument is the mode to use to hint the buffer.
local function hint_with(hint_mode, opts)
  local context = window.get_window_context(opts.direction)

  -- create the highlight groups; the highlight groups will allow us to clean everything at once when Hop quits
  local hl_ns = vim.api.nvim_create_namespace('hop_hl')
  local grey_cur_ns = vim.api.nvim_create_namespace('hop_grey_cur')

  -- create jump targets for the visible part of the buffer
  local jump_targets, jump_target_counts, indirect_jump_targets = jump_target.create_jump_targets_by_scanning_lines(
    hint_mode,
    opts
  )

  local h = nil
  if jump_target_counts == 0 then
    eprintln(' -> there’s no such thing we can see…', opts.teasing)
    clear_namespace(0, grey_cur_ns)
    return
  elseif jump_target_counts == 1 and opts.jump_on_sole_occurrence then
    for _, line_jump_targets in pairs(jump_targets) do
      if #line_jump_targets.jump_targets == 1 then
        jt = line_jump_targets.jump_targets[1]
        vim.api.nvim_win_set_cursor(0, { jt.line + 1, jt.col - 1})
        break
      end
    end

    clear_namespace(0, grey_cur_ns)
    return
  end

  -- we have at least two targets, so generate hints to display
  -- print(vim.inspect(indirect_jump_targets))
  local hints = hint.create_hints(jump_targets, indirect_jump_targets, opts)

  local hint_state = {
    hints = hints;
    hl_ns = hl_ns;
    grey_cur_ns = grey_cur_ns;
    top_line = context.top_line;
    bot_line = context.bot_line
  }

  -- grey everything out and add the virtual cursor
  grey_things_out(0, grey_cur_ns, context.top_line, context.bot_line, context.direction_mode)
  add_virt_cur(grey_cur_ns)
  hint.set_hint_extmarks(hl_ns, hints)
  vim.cmd('redraw')

  while h == nil do
    local ok, key = pcall(vim.fn.getchar)
    if not ok then
      M.quit(0, hint_state)
      break
    end
    local not_special_key = true
    -- :h getchar(): "If the result of expr is a single character, it returns a
    -- number. Use nr2char() to convert it to a String." Also the result is a
    -- special key if it's a string and its first byte is 128.
    --
    -- Note of caution: Even though the result of `getchar()` might be a single
    -- character, that character might still be multiple bytes.
    if type(key) == 'number' then
      key = vim.fn.nr2char(key)
    elseif key:byte() == 128 then
      not_special_key = false
    end

    if not_special_key and opts.keys:find(key, 1, true) then
      -- If this is a key used in Hop (via opts.keys), deal with it in Hop
      h = M.refine_hints(0, key, opts.teasing, hint_state)
      vim.cmd('redraw')
    else
      -- If it's not, quit Hop
      M.quit(0, hint_state)
      -- If the key captured via getchar() is not the quit_key, pass it through
      -- to nvim to be handled normally (including mappings)
      if key ~= vim.api.nvim_replace_termcodes(opts.quit_key, true, false, true) then
        vim.api.nvim_feedkeys(key, '', true)
      end
      break
    end
  end
end

-- Refine hints in the given buffer.
--
-- Refining hints allows to advance the state machine by one step. If a terminal step is reached, this function jumps to
-- the location. Otherwise, it stores the new state machine.
function M.refine_hints(buf_handle, key, teasing, hint_state)
  local h, hints, update_count = hint.reduce_hints_lines(hint_state.hints, key)

  if h == nil then
    if update_count == 0 then
      eprintln('no remaining sequence starts with ' .. key, teasing)
      return
    end

    hint_state.hints = hints

    clear_namespace(buf_handle, hint_state.hl_ns)
    hint.set_hint_extmarks(hint_state.hl_ns, hints)
    vim.cmd('redraw')
  else
    M.quit(buf_handle, hint_state)

    -- prior to jump, register the current position into the jump list
    vim.cmd("normal! m'")

    -- JUMP!
    vim.api.nvim_win_set_cursor(0, { h.jump_target.line + 1, h.jump_target.col - 1})
    return h
  end
end

-- Quit Hop and delete its resources.
--
-- This works only if the current buffer is Hop one.
function M.quit(buf_handle, hint_state)
  clear_namespace(buf_handle, hint_state.grey_cur_ns)
  clear_namespace(buf_handle, hint_state.hl_ns)
end

function M.hint_words(opts)
  hint_with(hint.by_word_start, get_command_opts(opts))
end

function M.hint_patterns(opts, pattern)
  opts = get_command_opts(opts)
  local cur_ns = vim.api.nvim_create_namespace('hop_grey_cur')

  -- The pattern to search is either retrieved from the (optional) argument
  -- or directly from user input.
  local pat
  if pattern then
    pat = pattern
  else
    add_virt_cur(cur_ns)
    vim.cmd('redraw')
    vim.fn.inputsave()
    local ok
    ok, pat = pcall(vim.fn.input, 'Search: ')
    vim.fn.inputrestore()
    if not ok then
      clear_namespace(0, cur_ns)
      return
    end
  end

  if #pat == 0 then
    eprintln('-> empty pattern', opts.teasing)
    clear_namespace(0, cur_ns)
    return
  end

  hint_with(hint.by_case_searching(pat, false, opts), opts)
end

function M.hint_char1(opts)
  opts = get_command_opts(opts)
  local cur_ns = vim.api.nvim_create_namespace('hop_grey_cur')
  add_virt_cur(cur_ns)
  vim.cmd('redraw')
  local ok, c = pcall(vim.fn.getchar)
  if not ok then
    clear_namespace(0, cur_ns)
    return
  end
  hint_with(hint.by_case_searching(vim.fn.nr2char(c), true, opts), opts)
end

function M.hint_char1_line(opts)
    opts = get_command_opts(opts)
    local ok, c = pcall(vim.fn.getchar)
    if not ok then return end
    hint_with(hint.by_case_searching_line(vim.fn.nr2char(c), true, opts), opts)
end

function M.hint_char2(opts)
  opts = get_command_opts(opts)
  local cur_ns = vim.api.nvim_create_namespace('hop_grey_cur')
  add_virt_cur(cur_ns)
  vim.cmd('redraw')
  local ok, a = pcall(vim.fn.getchar)
  if not ok then
    clear_namespace(0, cur_ns)
    return
  end
  local ok2, b = pcall(vim.fn.getchar)
  if not ok2 then
    clear_namespace(0, cur_ns)
    return
  end
  local pat = vim.fn.nr2char(a) .. vim.fn.nr2char(b)
  hint_with(hint.by_case_searching(pat, true, opts), opts)
end

function M.hint_lines(opts)
  hint_with(hint.by_line_start, get_command_opts(opts))
end

function M.hint_lines_skip_whitespace(opts)
  hint_with(hint.by_line_start_skip_whitespace(), get_command_opts(opts))
end

-- Setup user settings.
M.opts = defaults
function M.setup(opts)
  -- Look up keys in user-defined table with fallback to defaults.
  M.opts = setmetatable(opts or {}, {__index = defaults})

  -- Insert the highlights and register the autocommand if asked to.
  local highlight = require'hop.highlight'
  highlight.insert_highlights()

  if M.opts.create_hl_autocmd then
    highlight.create_autocmd()
  end
end

return M

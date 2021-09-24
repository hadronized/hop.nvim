local defaults = require'hop.defaults'
local hint = require'hop.hint'
local ui_util = require'hop.ui_util'

local M = {}

-- Allows to override global options with user local overrides.
local function get_command_opts(local_opts)
  -- In case, local opts are defined, chain opts lookup: [user_local] -> [user_global] -> [default]
  return local_opts and setmetatable(local_opts, {__index = M.opts}) or M.opts
end

function M.hint(hint_mode, opts)
  opts = get_command_opts(opts)
  local hl_ns = vim.api.nvim_create_namespace('')

  -- Create call hints for all windows from hint_states
  local hints, hint_opts = hint_mode.get_hint_list()
  -- cancelled
  if not hints then return end
  hint_opts = hint_opts or {}

  if #hints == 0 then
    ui_util.eprintln(' -> there’s no such thing we can see…', opts.teasing)
    return
  elseif opts.jump_on_sole_occurrence and #hints == 1 then
    -- search the hint and jump to it
    local h = hints[1]
    vim.api.nvim_set_current_win(h.handle.w)
    vim.api.nvim_win_set_cursor(h.handle.w, { h.line + 1, h.col - 1})
    return
  end

  -- mutate hint_list to add character targets
  hint.assign_character_targets(hints, opts)

  -- create the highlight group and grey everything out; the highlight group will allow us to clean everything at once
  -- when hop quits
  ui_util.grey_things_out(hl_ns, hint_opts)
  local bufs = ui_util.set_hint_extmarks(hl_ns, hints)
  vim.cmd('redraw')

  -- jump to hints
  local h = nil
  while h == nil do
    local ok, key = pcall(vim.fn.getchar)
    if not ok then
      ui_util.clear_all_ns(hl_ns, bufs, hint_opts)
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
      -- If this is a key used in hop (via opts.keys), deal with it in hop
      h, hints, bufs = M.refine_hints(key, opts.teasing, hl_ns, bufs, hint_opts, hints)
      vim.cmd('redraw')
    else
      -- If it's not, quit hop
      ui_util.clear_all_ns(hl_ns, bufs, hint_opts)

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
function M.refine_hints(key, teasing, hl_ns, bufs, hint_opts, hints)
  local h, update_hints = hint.reduce_hints(hints, key)

  if h == nil then
    if #update_hints == 0 then
      ui_util.eprintln('no remaining sequence starts with ' .. key, teasing)
      update_hints = hints
    else
      ui_util.grey_things_out(hl_ns, hint_opts)
      bufs = ui_util.set_hint_extmarks(hl_ns, update_hints)
      vim.cmd('redraw')
    end
  else
    ui_util.clear_all_ns(hl_ns, bufs, hint_opts)

    -- prior to jump, register the current position into the jump list
    vim.cmd("normal! m'")

    -- JUMP!
    vim.api.nvim_set_current_win(h.handle.w)
    vim.api.nvim_win_set_cursor(h.handle.w, { h.line + 1, h.col - 1})
  end

  return h, update_hints, bufs
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

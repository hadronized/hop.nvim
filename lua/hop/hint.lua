local perm = require'hop.perm'
local ui_util = require'hop.ui_util'

local M = {}
-- Turn a table representing a hint into a string.
local function tbl_to_str(hint)
  local s = ''

  for i = 1, #hint do
    s = s .. hint[i]
  end

  return s
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
function M.reduce_hints(hints, key)
  local output = {}

  for _, h in pairs(hints) do
    local prev_hint = h.hint
    h.hint = M.reduce_hint(h.hint, key)

    if h.hint == nil then
      return h
    elseif h.hint ~= prev_hint then
      output[#output + 1] = h
    end
  end

  return nil, output
end

function M.assign_character_targets(hints, comparator, opts)
  if comparator then
    if opts.reverse_distribution then
      comparator = function (a, b) return not comparator(a, b) end
    end

    table.sort(hints, comparator)
  end

  local perms = perm.permutations(opts.keys, #hints, opts)
  for i = 1, #hints do
    hints[i].hint = tbl_to_str(perms[i])
  end
end

-- Allows to override global options with user local overrides.
local function get_command_opts(local_opts)
  -- In case, local opts are defined, chain opts lookup: [user_local] -> [user_global] -> [default]
  return local_opts and setmetatable(local_opts, {__index = require"hop".opts}) or require"hop".opts
end

-- Refine hints in the given buffer.
--
-- Refining hints allows to advance the state machine by one step. If a terminal step is reached, this function jumps to
-- the location. Otherwise, it stores the new state machine.
function M.refine_hints(key, teasing, hl_ns, hint_opts, hints)
  local h, update_hints = M.reduce_hints(hints, key)

  if h == nil then
    if #update_hints == 0 then
      ui_util.eprintln('no remaining sequence starts with ' .. key, teasing)
      update_hints = hints
    else
      ui_util.grey_things_out(hl_ns, hint_opts)
      ui_util.set_hint_extmarks(hl_ns, update_hints)
      vim.cmd('redraw')
    end
  else
    ui_util.clear_all_ns(hl_ns)

    -- prior to jump, register the current position into the jump list
    vim.cmd("normal! m'")

    -- JUMP!
    if h.callback then h.callback() end
  end

  return h, update_hints
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
    if h.callback then h.callback() end
    return
  end

  -- mutate hint_list to add character targets
  M.assign_character_targets(hints, hint_mode.comparator, opts)

  -- create the highlight group and grey everything out; the highlight group will allow us to clean everything at once
  -- when hop quits
  ui_util.grey_things_out(hl_ns, hint_opts)
  ui_util.set_hint_extmarks(hl_ns, hints)
  vim.cmd('redraw')

  -- jump to hints
  local h = nil
  while h == nil do
    local ok, key = pcall(vim.fn.getchar)
    if not ok then
      ui_util.clear_all_ns(hl_ns)
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
      h, hints = M.refine_hints(key, opts.teasing, hl_ns, hint_opts, hints)
      vim.cmd('redraw')
    else
      -- If it's not, quit hop
      ui_util.clear_all_ns(hl_ns)

      -- If the key captured via getchar() is not the quit_key, pass it through
      -- to nvim to be handled normally (including mappings)
      if key ~= vim.api.nvim_replace_termcodes(opts.quit_key, true, false, true) then
        vim.api.nvim_feedkeys(key, '', true)
      end
      break
    end
  end
end

return M

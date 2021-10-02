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

---Reduce hint with key.
---
---If hint didn’t start with key, it is returned as-is. If hint started
---with key, that key is removed from its beginning. If the remaining
---hint is empty, `nil` is returned, otherwise the reduction is returned.
---
---@param hint string @the hint string to reduce
---@param key string @the character to reduce with (can be multi-byte)
---@return string|nil @(see description)
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

---Reduce all hints and return the one fully reduced, if any.
---@param hints Hint[] @the list of hints to reduce
---@param key string @the character to reduce with (can be multi-byte)
---@return Hint|nil @a hint was reduced fully if there was one, otherwise nil
---@return Hint[]|nil @the reduced list of hints if no hint was reduced fully, otherwise nil
function M.reduce_hints(hints, key)
  local output = {}

  for _, h in pairs(hints) do
    local prev_target = h.target
    h.target = M.reduce_hint(h.target, key)

    if h.target == nil then
      return h
    elseif h.target ~= prev_target then
      output[#output + 1] = h
    end
  end

  return nil, output
end

---Assign target strings to the hints in the given list, ordered by the given comparator.
---@param hints Hint[] @the hints to assign targets to
---@param comparator fun(a:Hint,b:Hint):boolean @the `table.sort` comparator function to use to sort hints
---@param opts table @hop.nvim options
function M.assign_character_targets(hints, comparator, opts)
  if comparator then
    if opts.reverse_distribution then
      ---@param a Hint
      ---@param b Hint
      comparator = function (a, b) return not comparator(a, b) end
    end

    table.sort(hints, comparator)
  end

  local perms = perm.permutations(opts.keys, #hints, opts)
  for i = 1, #hints do
    hints[i].target = tbl_to_str(perms[i])
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
      if hint_opts.grey_out then
        ui_util.grey_things_out(hl_ns, hint_opts.grey_out)
      end
      ui_util.set_hint_extmarks(hl_ns, update_hints)
      vim.cmd('redraw')
    end
  else
    ui_util.clear_all_ns(hl_ns)
  end

  return h, update_hints
end

---A hint that can be "hopped to".
---@class Hint
---@field target string @the UI string used for reducing to and selecting this hint
---@field callback fun() @the callback to invoke when this hint is selected (overrides Strategy.callback)
---@field buf number @this hint's buffer
---@field line number @this hint's line number (1-indexed)
---@field col number @this hint's start column number (inclusive, 1-indexed byte-based)
---@field col_end number @this hint's end column number (inclusive, 1-indexed byte-based)

---Set of a range of lines to grey out in a buffer.
---@class GreyOutBuf
---@field buf number @the buffer to grey out
---@field ranges table[] @a list of {start = ..., end = ...} ranges to grey out in this buf, where `...` are (1,0)-indexed (line,row) positions

---UI-related options controlling how hints are displayed.
---@class HintOpts
---@field grey_out GreyOutBuf[]

---A method for generating and using hints.
---@class Strategy
---@field get_hint_list fun():Hint[]|nil,table @function to get list of hints, returns nil to indicate cancellation,second
---@field comparator fun(a:Hint,b:Hint):boolean @the `table.sort` comparator function to use to sort hints
---@field callback fun(h:Hint) @the callback to invoke when a hint is selected (overriden by Hint.callback)

---The "core" function of hop.nvim that generates, organizes, and displays hints.
---@param strategy Strategy @the strategy to use
---@param opts table @hop.nvim options
function M.hint(strategy, opts)
  opts = get_command_opts(opts)
  local hl_ns = vim.api.nvim_create_namespace('')

  -- Create call hints for all windows from hint_states
  local hints, hint_opts = strategy.get_hint_list()
  -- cancelled
  if not hints then return end
  hint_opts = hint_opts or {}

  ---@param h Hint
  local function jump(h)
    local callback = h.callback or strategy.callback and function() strategy.callback(h) end
    if callback then callback() end
  end

  if #hints == 0 then
    ui_util.eprintln(' -> there’s no such thing we can see…', opts.teasing)
    return
  elseif opts.jump_on_sole_occurrence and #hints == 1 then
    -- search the hint and jump to it
    jump(hints[1])
    return
  end

  -- mutate hint_list to add character targets
  M.assign_character_targets(hints, strategy.comparator, opts)

  -- create the highlight group and grey everything out; the highlight group will allow us to clean everything at once
  -- when hop quits
  if hint_opts.grey_out then
    ui_util.grey_things_out(hl_ns, hint_opts.grey_out)
  end
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

      if h then
        jump(h)
      end
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

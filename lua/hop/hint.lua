local perm = require'hop.perm'
local prio = require'hop.priority'

local M = {}

M.HintDirection = {
  BEFORE_CURSOR = 1,
  AFTER_CURSOR = 2,
}

-- I hate Lua.
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, vim.fn.byteidx(s, 1))
  return f:upper() == f
end

-- Regex hint mode.
--
-- Used to hint result of a search.
function M.by_searching(pat, plain_search)
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
    end
  }
end

-- Current line hint mode
--
-- Used to constrain scope of hopping to current line only
function M.by_case_searching_line(pat, plain_search, opts)
    local m = M.by_case_searching(pat, plain_search, opts)
    m.curr_line_only = true

    return m
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
    end
  }
end

local function tbl_to_str(label)
  local s = ''

  for i = 1, #label do
    s = s .. label[i]
  end

  return s
end

-- Reduce a hint.
--
-- This function will remove hints not starting with the input key and will reduce the other ones
-- with one level.
local function reduce_label(label, key)
  local snd_idx = vim.fn.byteidx(label, 1)
  if label:sub(1, snd_idx) == key then
    label = label:sub(snd_idx + 1)
  end

  if label == '' then
    label = nil
  end

  return label
end

-- Reduce all hints and return the one fully reduced, if any.
function M.reduce_hints_lines(per_line_hints, key)
  local output = {}
  local update_count = 0

  for _, line_hints in pairs(per_line_hints) do
    local next_hints = {}

    for _, h in pairs(line_hints) do
      local prev_label = h.label
      h.label = reduce_label(h.label, key)

      if h.label == nil then
        return h
      elseif h.label ~= prev_label then
        next_hints[#next_hints + 1] = h
        update_count = update_count + 1
      end
    end

    output[#output + 1] = next_hints
  end

  return nil, output, update_count
end

-- Create hints from jump targets.
--
-- This function associates jump targets with permutations, creating hints. A hint is then a jump target along with a
-- label.
function M.create_hints(jump_targets, indirect_jump_targets, opts)
  local hints = {}
  local perms = perm.permutations(opts.keys, #indirect_jump_targets, opts)

  for i, indirect in pairs(indirect_jump_targets) do
    if hints[indirect.i] == nil then
      hints[indirect.i] = {}
    end

    hints[indirect.i][indirect.j] = {
      label = tbl_to_str(perms[i]),
      jump_target = jump_targets[indirect.i][indirect.j]
    }
  end

  return hints
end

-- Create the extmarks for per-line hints.
function M.set_hint_extmarks(hl_ns, per_line_hints)
  for _, hints in pairs(per_line_hints) do
    for _, hint in pairs(hints) do
      if hint.jump_target == nil then
        print('holy fuck', vim.inspect(hint))
      end
      if vim.fn.strdisplaywidth(hint.label) == 1 then
        vim.api.nvim_buf_set_extmark(hint.jump_target.buffer, hl_ns, hint.jump_target.line, hint.jump_target.column - 1, {
          virt_text = { { hint.label, "HopNextKey" } },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
          priority = prio.HINT_PRIO
        })
      else
        -- get the byte index of the second hint so that we can slice it correctly
        local snd_idx = vim.fn.byteidx(hint.label, 1)
        vim.api.nvim_buf_set_extmark(hint.jump_target.buffer, hl_ns, hint.jump_target.line, hint.jump_target.column - 1, {
          virt_text = { { hint.label:sub(1, snd_idx), "HopNextKey1" }, { hint.label:sub(snd_idx + 1), "HopNextKey2" } },
          virt_text_pos = 'overlay',
          hl_mode = 'combine',
          priority = prio.HINT_PRIO
        })
      end
    end
  end
end

return M

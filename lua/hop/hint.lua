local perm = require'hop.perm'
local prio = require'hop.priority'

local M = {}

M.HintDirection = {
  BEFORE_CURSOR = 1,
  AFTER_CURSOR = 2,
}

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
function M.reduce_hints(hints, key)
  local next_hints = {}

  for _, h in pairs(hints) do
      local prev_label = h.label
      h.label = reduce_label(h.label, key)

      if h.label == nil then
        return h
      elseif h.label ~= prev_label then
        next_hints[#next_hints + 1] = h
      end
  end

  return nil, next_hints
end

-- Create hints from jump targets.
--
-- This function associates jump targets with permutations, creating hints. A hint is then a jump target along with a
-- label.
function M.create_hints(jump_targets, indirect_jump_targets, opts)
  local hints = {}
  local perms = perm.permutations(opts.keys, #jump_targets, opts)

  for i, indirect in pairs(indirect_jump_targets) do
    hints[indirect.index] = {
      label = tbl_to_str(perms[i]),
      jump_target = jump_targets[indirect.index]
    }
  end

  return hints
end

-- Create the extmarks for per-line hints.
function M.set_hint_extmarks(hl_ns, hints)
  for _, hint in pairs(hints) do
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
      vim.api.nvim_buf_set_extmark(hint.jump_target.buffer, hl_ns, hint.jump_target.line, hint.jump_target.column - 1, { -- HERE
        virt_text = { { hint.label:sub(1, snd_idx), "HopNextKey1" }, { hint.label:sub(snd_idx + 1), "HopNextKey2" } },
        virt_text_pos = 'overlay',
        hl_mode = 'combine',
        priority = prio.HINT_PRIO
      })
    end
  end
end

return M

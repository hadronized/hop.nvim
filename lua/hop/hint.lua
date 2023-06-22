local perm = require('hop.perm')
local prio = require('hop.priority')

---@class Hint
---@field label? string
---@field jump_target JumpTarget

---@class HintState
---@field buf_list number[]
---@field all_ctxs Context
---@field hints Hint[]
---@field hl_ns number
---@field dim_ns number
---@field diag_ns table
---@field cursorline boolean

local M = {}

---@enum HintDirection
M.HintDirection = {
  BEFORE_CURSOR = 1,
  AFTER_CURSOR = 2,
}

---@enum HintPosition
M.HintPosition = {
  BEGIN = 1,
  MIDDLE = 2,
  END = 3,
}

---@enum HintType
M.HintType = {
  OVERLAY = 'overlay',
  INLINE = 'inline',
}

---@param label table
---@return string
local function tbl_to_str(label)
  local s = ''

  for i = 1, #label do
    s = s .. label[i]
  end

  return s
end

-- Reduce a hint.
-- This function will remove hints not starting with the input key and will reduce the other ones
-- with one level.
---@param label string
---@param key string
---@return string?
local function reduce_label(label, key)
  local snd_idx = vim.fn.byteidx(label, 1)
  if label:sub(1, snd_idx) == key then
    label = label:sub(snd_idx + 1)
  end

  if label == '' then
    return nil
  end

  return label
end

-- Reduce all hints and return the one fully reduced, if any.
---@param hints Hint[]
---@param key string
---@return Hint?,Hint[]
function M.reduce_hints(hints, key)
  local next_hints = {}

  for _, h in pairs(hints) do
    local prev_label = h.label
    h.label = reduce_label(h.label, key)

    if h.label == nil then
      return h, {}
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
--
-- If `indirect_jump_targets` is `nil`, `jump_targets` is assumed already ordered with all jump target with the same
-- score (0)
---@param jump_targets JumpTarget[]
---@param indirect_jump_targets IndirectJumpTarget[]
---@param opts Options
---@return Hint[]
function M.create_hints(jump_targets, indirect_jump_targets, opts)
  ---@type Hint[]
  local hints = {}
  local perms = perm.permutations(opts.keys, #jump_targets, opts)

  -- get or generate indirect_jump_targets
  if indirect_jump_targets == nil then
    indirect_jump_targets = {}

    for i = 1, #jump_targets do
      indirect_jump_targets[i] = { index = i, score = 0 }
    end
  end

  for i, indirect in pairs(indirect_jump_targets) do
    hints[indirect.index] = {
      label = tbl_to_str(perms[i]),
      jump_target = jump_targets[indirect.index],
    }
  end

  return hints
end

-- Create the extmarks for per-line hints.
---@param hl_ns number
---@param hints Hint[]
---@param opts Options
function M.set_hint_extmarks(hl_ns, hints, opts)
  for _, hint in pairs(hints) do
    local label = hint.label
    if opts.uppercase_labels and label ~= nil then
      label = label:upper()
    end

    local col = hint.jump_target.column - 1

    local virt_text = { { label, 'HopNextKey' } }
    -- get the byte index of the second hint so that we can slice it correctly
    if label ~= nil and vim.fn.strdisplaywidth(label) ~= 1 then
      local snd_idx = vim.fn.byteidx(label, 1)
      virt_text = { { label:sub(1, snd_idx), 'HopNextKey1' }, { label:sub(snd_idx + 1), 'HopNextKey2' } }
    end

    vim.api.nvim_buf_set_extmark(hint.jump_target.buffer or 0, hl_ns, hint.jump_target.line, col, {
      virt_text = virt_text,
      virt_text_pos = opts.hint_type,
      hl_mode = 'combine',
      priority = prio.HINT_PRIO,
    })
  end
end

---@param hl_ns number
---@param jump_targets JumpTarget[]
function M.set_hint_preview(hl_ns, jump_targets)
  for _, jt in ipairs(jump_targets) do
    vim.api.nvim_buf_set_extmark(jt.buffer, hl_ns, jt.line, jt.column - 1, {
      end_row = jt.line,
      end_col = jt.column - 1 + jt.length,
      hl_group = 'HopPreview',
      hl_eol = true,
      priority = prio.HINT_PRIO,
    })
  end
end

return M

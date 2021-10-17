local M = {}
local constants = require'hop.constants'

local ns_to_bufs = {}

---A hack to prevent #57 by deleting twice the namespace (it’s super weird).
---@param buf_handle number @the buffer to clear
---@param hl_ns number @the namespace ID to clear
function M.clear_ns(buf_handle, hl_ns)
  if vim.api.nvim_buf_is_valid(buf_handle) then
    vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, 0, -1)
  end
  if ns_to_bufs[hl_ns] then ns_to_bufs[hl_ns][buf_handle] = nil end
end

---Quit Hop and delete its resources.
---@param hl_ns number @the namespace ID to clear
function M.clear_all_ns(hl_ns)
  if not ns_to_bufs[hl_ns] then return end
  for buf, _ in pairs(ns_to_bufs[hl_ns]) do
    M.clear_ns(buf, hl_ns)
  end
  ns_to_bufs[hl_ns] = nil
end

---Register this buf as using the given namespace (so it can be retrieved when clearing this namespace).
---@param hl_ns number @the namespace ID to clear
---@param buf number @the buffer to register
function M.ns_register_buf(hl_ns, buf)
  ns_to_bufs[hl_ns] = ns_to_bufs[hl_ns] or {}
  ns_to_bufs[hl_ns][buf] = true
end

---Grey everything out to prepare the Hop session.
---@param hl_ns number @the highlight namespace.
---@param grey_out GreyOutBuf[] @in which the lnums in the buffer need to be highlighted
function M.grey_things_out(hl_ns, grey_out)
  M.clear_all_ns(hl_ns)
  for _, hl_buf_data in ipairs(grey_out) do
    local buf = hl_buf_data.buf
    if not vim.api.nvim_buf_is_valid(buf) then goto __NEXT_HH end

    for _, range in ipairs(hl_buf_data.ranges) do
      local start, _end = range.start, range['end']
      vim.api.nvim_buf_set_extmark(buf, hl_ns, start[1], start[2] < 0 and 0 or start[2], {
        end_line = _end[1],
        end_col = _end[2] < 0 and 0 or _end[2],
        hl_group = 'HopUnmatched',
        hl_eol = true,
        priority = constants.GREY_PRIO
      })
    end
    M.ns_register_buf(hl_ns, buf)

    ::__NEXT_HH::
  end
end

-- Add the virtual cursor, taking care to handle the cases where:
-- - the virtualedit option is being used and the cursor is in a
--   tab character or past the end of the line
-- - the current line is empty
-- - there are multibyte characters on the line
function M.add_virt_cur(ns)
  local cur_info = vim.fn.getcurpos()
  local cur_row = cur_info[2] - 1
  local cur_col = cur_info[3] - 1 -- this gives cursor column location, in bytes
  local cur_offset = cur_info[4]
  local virt_col = cur_info[5] - 1
  local cur_line = vim.api.nvim_get_current_line()

  -- first check to see if cursor is in a tab char or past end of line
  if cur_offset ~= 0 then
    vim.api.nvim_buf_set_extmark(0, ns, cur_row, cur_col, {
      virt_text = {{'<E2><96><88>', 'Normal'}},
      virt_text_win_col = virt_col,
      priority = constants.CURSOR_PRIO
    })
  -- otherwise check to see if cursor is at end of line or on empty line
  elseif #cur_line == cur_col then
    vim.api.nvim_buf_set_extmark(0, ns, cur_row, cur_col, {
      virt_text = {{'<E2><96><88>', 'Normal'}},
      virt_text_pos = 'overlay',
      priority = constants.CURSOR_PRIO
    })
  else
    vim.api.nvim_buf_set_extmark(0, ns, cur_row, cur_col, {
      -- end_col must be column of next character, in bytes
      end_col = vim.fn.byteidx(cur_line, vim.fn.charidx(cur_line, cur_col) + 1),
      hl_group = 'HopCursor',
      priority = constants.CURSOR_PRIO
    })
  end
end

---Display error messages.
---@param msg string @the message to display
---@param teasing boolean @whether to actually show the message
function M.eprintln(msg, teasing)
  if teasing then
    vim.api.nvim_echo({{msg, 'Error'}}, true, {})
  end
end

---Highlight everything marked from pat_mode
---@param hl_ns number @the highlight namespace to use
---@param hints Hint[] @list of hints to highlight
function M.highlight_things_out(hl_ns, hints)
  M.clear_all_ns(hl_ns)
  for _, h in ipairs(hints) do
    vim.api.nvim_buf_add_highlight(h.buf, hl_ns, 'HopPreview', h.line - 1, h.col - 1, h.col_end - 1)
    M.ns_register_buf(hl_ns, h.buf)
  end
end

---Add extmarks for the given hints using their target strings.
---@param hl_ns number @the highlight namespace to use
---@param hints Hint[] @list of hints to highlight
function M.set_hint_extmarks(hl_ns, hints)
  M.clear_all_ns(hl_ns)
  for _, h in pairs(hints) do
    local hbuf = h.buf
    if not vim.api.nvim_buf_is_valid(hbuf) then
      goto __NEXT_HH
    end

    if vim.fn.strdisplaywidth(h.target) == 1 then
      vim.api.nvim_buf_set_extmark(
        hbuf,
        hl_ns,
        h.line - 1, h.col - 1,
        {
          virt_text = { { h.target, "HopNextKey" } };
          virt_text_pos = 'overlay';
          hl_mode = 'combine';
          priority = constants.HINT_PRIO
        })
    else
      -- get the byte index of the second hint so that we can slice it correctly
      local snd_idx = vim.fn.byteidx(h.target, 1)
      vim.api.nvim_buf_set_extmark(
        hbuf,
        hl_ns,
        h.line - 1, h.col - 1,
        {
          virt_text = { { h.target:sub(1, snd_idx), "HopNextKey1" }, { h.target:sub(snd_idx + 1), "HopNextKey2" } };
          virt_text_pos = 'overlay';
          hl_mode = 'combine';
          priority = constants.HINT_PRIO
        })
    end
    M.ns_register_buf(hl_ns, hbuf)

    ::__NEXT_HH::
  end
end

return M

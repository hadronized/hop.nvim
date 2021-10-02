local M = {}

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
    M.clear_ns(buf, hl_ns)

    for _, range in ipairs(hl_buf_data.ranges) do
      vim.highlight.range(
        buf,
        hl_ns,
        'HopUnmatched',
        range.start,
        range['end']
      )
      M.ns_register_buf(hl_ns, buf)
    end

    ::__NEXT_HH::
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
  for _, h in ipairs(hints) do
    vim.api.nvim_buf_add_highlight(h.buf, hl_ns, 'HopPreview', h.line - 1, h.col - 1, h.col_end - 1)
    M.ns_register_buf(hl_ns, h.buf)
  end
end

---Add extmarks for the given hints using their target strings.
---@param hl_ns number @the highlight namespace to use
---@param hints Hint[] @list of hints to highlight
function M.set_hint_extmarks(hl_ns, hints)
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
          virt_text_pos = 'overlay'
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
          virt_text_pos = 'overlay'
        })
    end
    M.ns_register_buf(hl_ns, hbuf)

    ::__NEXT_HH::
  end
end

return M

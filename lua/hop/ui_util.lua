local M = {}

-- A hack to prevent #57 by deleting twice the namespace (it’s super weird).
function M.clear_ns(buf_handle, hl_ns)
  if vim.api.nvim_buf_is_valid(buf_handle) then
    vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, 0, -1)
    vim.api.nvim_buf_clear_namespace(buf_handle, hl_ns, 0, -1)
  end
end

-- Quit Hop and delete its resources.
function M.clear_all_ns(hl_ns, bufs, hint_opts)
  local cleared_buf = {}

  local function clear_buf(buf)
    if not cleared_buf[buf] then M.clear_ns(buf, hl_ns) end
    cleared_buf[buf] = true
  end

  for _, buf in ipairs(bufs) do
    clear_buf(buf)
  end

  if hint_opts.grey_out then
    for _, hl_buf_data in ipairs(hint_opts.grey_out) do
      local buf = hl_buf_data.buf
      clear_buf(buf)
    end
  end
end

-- Grey everything out to prepare the Hop session.
--
-- - hl_ns is the highlight namespace.
-- - hint_opts in which the lnums in the buffer need to be highlighted
function M.grey_things_out(hl_ns, hint_opts)
  if not hint_opts.grey_out then return end
  for _, hl_buf_data in ipairs(hint_opts.grey_out) do
    local buf = hl_buf_data.buf
    if not vim.api.nvim_buf_is_valid(buf) then goto __NEXT_HH end
    M.clear_ns(buf, hl_ns)

    for _, range in ipairs(hl_buf_data.ranges) do
      vim.api.nvim_buf_add_highlight(buf, hl_ns, 'HopUnmatched', range.line, range.col_start, range.col_end)
    end

    ::__NEXT_HH::
  end
end

-- Display error messages.
function M.eprintln(msg, teasing)
  if teasing then
    vim.api.nvim_echo({{msg, 'Error'}}, true, {})
  end
end

local function to_list(set)
  local list = {}
  for item, _ in pairs(set) do
    list[#list + 1] = item
  end
  return list
end

-- Highlight everything marked from pat_mode
-- - pat_mode if provided, highlight the pattern
function M.highlight_things_out(hl_ns, hints)
  local bufs = {}
  for _, h in ipairs(hints) do
    vim.api.nvim_buf_add_highlight(h.handle.b, hl_ns, 'HopPreview', h.line, h.col - 1, h.col_end - 1)
    bufs[h.handle.b] = true
  end

  return to_list(bufs)
end

function M.set_hint_extmarks(hl_ns, hints)
  local bufs = {}
  for _, h in pairs(hints) do
    local hbuf = h.handle.b
    if not vim.api.nvim_buf_is_valid(hbuf) then
      goto __NEXT_HH
    end
    bufs[hbuf] = true

    if vim.fn.strdisplaywidth(h.hint) == 1 then
      vim.api.nvim_buf_set_extmark(
        hbuf,
        hl_ns,
        h.line, h.col - 1,
        {
          virt_text = { { h.hint, "HopNextKey" } };
          virt_text_pos = 'overlay'
        })
    else
      -- get the byte index of the second hint so that we can slice it correctly
      local snd_idx = vim.fn.byteidx(h.hint, 1)
      vim.api.nvim_buf_set_extmark(
        hbuf,
        hl_ns,
        h.line, h.col - 1,
        {
          virt_text = { { h.hint:sub(1, snd_idx), "HopNextKey1" }, { h.hint:sub(snd_idx + 1), "HopNextKey2" } };
          virt_text_pos = 'overlay'
        })
    end

    ::__NEXT_HH::
  end

  return to_list(bufs)
end

return M

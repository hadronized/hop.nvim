local M = {}

--- yanks the text to specified register
---@param text string[]
---@param register string
M.yank_to = function(text, register)
  vim.fn.setreg(register, text)
end

--- yanks the text to specified register
---@param register string
---@param target JumpTarget
M.paste_from = function(target, register)
  local text = vim.fn.getreg(register)
  if text == '' then
    return
  end

  local replacement = vim.split(text, '\n', { trimempty = true })
  vim.api.nvim_buf_set_text(0, target.line, target.column, target.line, target.column, replacement)
end

--- checks the range bounds and when end is before the start swaps theme
---@param start_range JumpTarget
---@param end_range JumpTarget
---@return JumpTarget,JumpTarget
local function check_bounds(start_range, end_range)
  if start_range.line < end_range.line then
    return start_range, end_range
  elseif start_range.line == end_range.line and start_range.column <= end_range.column then
    return start_range, end_range
  end
  return end_range, start_range
end

--- returns the text in the range for current buffer
---@param start_range JumpTarget
---@param end_range JumpTarget
---@return string[]
M.get_text = function(start_range, end_range)
  start_range, end_range = check_bounds(start_range, end_range)
  return vim.api.nvim_buf_get_text(0, start_range.line, start_range.column, end_range.line, end_range.column, {})
end

return M

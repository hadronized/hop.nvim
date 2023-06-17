---@class Options
---@field direction HintDirection
local M = {}

local hint = require('hop.hint')

M.keys = 'asdghklqwertyuiopzxcvbnmfj'
M.quit_key = '<Esc>'
M.perm_method = require('hop.perm').TrieBacktrackFilling
M.reverse_distribution = false
M.x_bias = 10
M.teasing = true
M.jump_on_sole_occurrence = true
M.case_insensitive = true
M.create_hl_autocmd = true
M.current_line_only = false
M.dim_unmatched = true
M.uppercase_labels = false
M.multi_windows = false
M.hint_position = hint.HintPosition.BEGIN ---@type HintPosition
M.hint_offset = 0
M.hint_type = hint.HintType.OVERLAY ---@type HintType
M.excluded_filetypes = {}
M.yank_register = ''

return M

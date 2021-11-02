local M = {}

M.keys = 'asdghklqwertyuiopzxcvbnmfj'
M.quit_key = '<Esc>'
M.perm_method = require'hop.perm'.TrieBacktrackFilling
M.reverse_distribution = false
M.teasing = true
M.jump_on_sole_occurrence = true
M.case_insensitive = true
M.create_hl_autocmd = true
M.current_line_only = false

return M

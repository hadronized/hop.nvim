local M = {}

M.keys = 'asdghklqwertyuiopzxcvbnmfj'
M.quit_key = '<Esc>'
M.perm_method = require'hop.perm'.TrieBacktrackFilling
M.reverse_distribution = false
M.term_seq_bias = 3 / 4
M.teasing = true
M.jump_on_sole_occurrence = true
M.create_hl_autocmd = true

return M

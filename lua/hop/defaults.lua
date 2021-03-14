local M = {}

M.keys = 'asdghklqwertyuiopzxcvbnmfj'
M.perm_method = require'hop.perm'.TrieBacktrackFilling
M.reverse_distribution = false
M.term_seq_bias = 3 / 4
M.winblend = 50
M.teasing = true
M.jump_on_sole_occurrence = true

return M

local M = {}

M.keys = 'asdghklqwertyuiopzxcvbnmfj'
M.quit_key = '<Esc>'
M.perm_method = require'hop.perm'.TrieBacktrackFilling
M.reverse_distribution = false
M.term_seq_bias = 3 / 4
M.teasing = true
M.jump_on_sole_occurrence = true
M.case_insensitive = true
M.create_hl_autocmd = true
M.use_migemo = false
M.migemo_cmd = 'cmigemo'
M.migemo_dict = '/usr/local/opt/cmigemo/share/migemo/utf-8/migemo-dict'
M.migemo_debug = false

return M

-- Options.
local opt_winblend = 50
local opt_keys = 'etisuranvdplqxgyhfmjzwk'
local opt_reverse_distribution = false

local hint_buf_id = nil
local M = {}

-- Create the keymap based on the input keys.
local function create_jump_keymap(buf_id, keys)
  -- remap all the jump keys
  for i = 1, #keys do
    local key = keys:sub(i, i)
    vim.api.nvim_buf_set_keymap(buf_id, '', key, '<cmd>lua require"./lua/easymotion-lua/init":refine_hints(\'' .. key .. '\')<cr>', { nowait = true })
  end

  vim.api.nvim_buf_set_keymap(buf_id, '', '<esc>', '<cmd>q<cr>', {})
end

-- Returns the index of all the words in a string.
local word_reg = vim.regex('\\<\\w\\+')
local function get_words(line_nr, line)
  local words = {}

  local col = 1
  while true do
    local s = line:sub(col)
    local b, e = word_reg:match_str(s)

    if b == nil then
      break
    end

    words[#words + 1] = { line = line_nr; col = vim.str_utfindex(line, col + b) }

    col = col + e
  end

  return words
end

-- Get the first key.
local function first_key(keys)
  return keys:sub(1, 1)
end

-- Get the next key, if any, or return nil.
local function next_key(keys, key)
  local i = keys:find(key)

  if i == #keys then
    return nil
  end

  local i1 = i + 1
  return keys:sub(i1, i1)
end

local function next_perm(term_keys, seq_keys, perm)
  local perm_len = #perm

  -- terminal key
  local term_key = next_key(term_keys, perm[perm_len])

  if term_key then
    perm[perm_len] = term_key

    return perm
  end

  perm[perm_len] = first_key(term_keys)

  -- sequence keys
  for i = perm_len - 1, 1, -1 do
    local seq_key = next_key(seq_keys, perm[i])

    if seq_key then
      perm[i] = seq_key

      return perm
    else
      perm[i] = first_key(seq_keys)
    end
  end

  -- we need to increment the dimension
  perm[perm_len] = first_key(seq_keys)
  perm[perm_len + 1] = first_key(term_keys)

  return perm
end

-- Get the first N permutations for a given set of keys.
--
-- The way it works is by incrementing a permutation as long it doesn’t reach a sequence key in the keys collection. A
-- sequence key is a key in the last ¼ part of the initial keys collection. For instance, for keys = "abcdefghijklmnop",
-- "mnop" is the last ¼ part, so those keys will be used as sequence-keys. The invariant is that, when all the
-- permutations are generated, any permutation for which the last key is in the ¾ part of keys implies that permutations
-- at the same level cannot have this key. Said otherwise, terminal sequences cannot share their last key with
-- non-terminal sequences on the same level. The following are then not possible (given the example keys from above):
--
-- - "a", "ab": not possible because even though "b" is okay, "a" is terminal for the first sequence, so it cannot be
--   used in the second.
-- - "a", "ma", "mb", mc": okay, as "a" is not shared on the same level.
-- - "pnac": without even going any further, this sequence is not possible as "a" is only used in terminal sequences, so
--   this "pnac" sequence would collide with the correct "pna" sequence.
--
-- Permutations are sorted by dimensions, so you will get 1-perm first, then 2-perm, 3-perm, etc. depending on the size
-- of the keys.
local function permutations(keys, n)
  local quarter = #keys * 3 / 4
  local term_keys = keys:sub(1, quarter)
  local seq_keys = keys:sub(quarter + 1)
  local perms = {}
  local perm = { keys:sub(1, 1) }

  for i = 1, n do
    perm = next_perm(term_keys, seq_keys, perm)
    perms[#perms + 1] = vim.deepcopy(perm)
  end

  return perms
end

-- Manhattan distance with column and row, weighted on x so that results are more packed on y.
local function manh_dist(a, b, x_bias)
  local bias = x_bias or 10
  return bias * math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
end

-- Turn a table into a string.
local function tbl_to_str(hint)
  local s = ''

  for i = 1, #hint do
    s = s .. hint[i]
  end

  return s
end

-- Reduce a hint.
--
-- This function will remove hints not starting with the input key and will reduce the other ones
-- with one level.
local function reduce_hint(hint, key)
  if hint:sub(1, 1) == key then
    hint = hint:sub(2)
  end

  if hint == '' then
    hint = nil
  end

  return hint
end

-- Reduce all words’ hints and return the word for which the hint is fully reduced, if any.
local function reduce_words(per_line_words, key)
  local output = {}

  for _, words in pairs(per_line_words) do
    local next_words = {}

    for _, word in pairs(words) do
      local prev_hint = word.hint
      word.hint = reduce_hint(word.hint, key)

      if word.hint == nil then
        return word
      elseif prev_hint ~= word.hint then
        next_words[#next_words + 1] = word
      end
    end

    output[#output + 1] = next_words
  end

  return nil, output
end

-- Update the hint buffer.
local function update_hint_buffer(buf_id, buf_width, buf_height, per_line_words)
  local new_lines = {}
  for line = 1, buf_height do
    local col = 1
    local content = ''

    for _, w in pairs(per_line_words[line]) do
      -- put spaces until we hit the beginning of the word
      if col < w.col then
        content = content .. string.rep(' ', w.col - col)
      end

      content = content .. w.hint
      col = w.col + #w.hint
    end

    if col < buf_width then
      content = content .. string.rep(' ', buf_width - col)
    end

    new_lines[line] = content
  end

  vim.api.nvim_buf_set_lines(hint_buf_id, 0, -1, true, new_lines)

  for line = 1, buf_height do
    vim.api.nvim_buf_add_highlight(hint_buf_id, -1, 'EndOfBuffer', line, 0, -1)

    for _, w in pairs(per_line_words[line]) do
      local hint_len = #w.hint

      if hint_len == 1 then
        vim.api.nvim_buf_add_highlight(hint_buf_id, -1, 'VroomNextKey', w.line - 1, w.col - 1, w.col)
      else
        vim.api.nvim_buf_add_highlight(hint_buf_id, -1, 'VroomNextKey1', w.line - 1, w.col - 1, w.col)
        vim.api.nvim_buf_add_highlight(hint_buf_id, -1, 'VroomNextKey2', w.line - 1, w.col, w.col + #w.hint - 1)
      end
    end
  end
end

function M:open_hint_window()
  local win_view = vim.fn.winsaveview()
  local cursor_line = win_view['lnum']
  local cursor_col = win_view['col']
  local win_top_line = win_view['topline'] - 1
  local screenpos = vim.fn.screenpos(0, cursor_line, 0)
  local cursor_pos = { screenpos.row, cursor_col }
  local buf_width = vim.api.nvim_win_get_position(0)[2] + vim.api.nvim_win_get_width(0) - screenpos.col + 1
  local buf_height = vim.api.nvim_win_get_height(0)
  local win_lines = vim.api.nvim_buf_get_lines(0, win_top_line, win_top_line + buf_height, false)

  if #win_lines < buf_height then
    buf_height = #win_lines
  end

  -- extract all the words currently visible on screen; the per_line_words variable contains the list
  -- of words as a pair of { line, column } for each word on a given line and indirect_words is a
  -- simple list containing { line, word_index, distance_to_cursor } that is sorted by distance to
  -- cursor, allowing to zip this list with the hints and distribute the hints
  local per_line_words = {}
  local indirect_words = {}
  for i = 1, buf_height do
    local wds = get_words(i, win_lines[i])
    per_line_words[i] = wds

    for j = 1, #wds do
      local w = wds[j]
      indirect_words[#indirect_words + 1] = { i = i; j = j; dist = manh_dist(cursor_pos, { w.line, w.col }) }
    end
  end

  local dist_comparison = nil
  if opt_reverse_distribution then
    dist_comparison = function (a, b) return a.dist > b.dist end
  else
    dist_comparison = function (a, b) return a.dist < b.dist end
  end

  table.sort(indirect_words, dist_comparison)

  -- generate permutations and update the lines with hints
  local hints = permutations(opt_keys, #indirect_words)
  for i, indirect in pairs(indirect_words) do
    per_line_words[indirect.i][indirect.j].hint = tbl_to_str(hints[i])
  end

  -- create a new buffer to contain the hints
  hint_buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_var(hint_buf_id, 'foo', 'test')

  -- fill the hint buffer
  update_hint_buffer(hint_buf_id, buf_width, buf_height, per_line_words)

  local win_id = vim.api.nvim_open_win(hint_buf_id, true, {
    relative = 'win',
    width = buf_width,
    height = buf_height,
    row = 0,
    col = 0,
    bufpos = { win_top_line, 0 },
    style = 'minimal'
  })
  vim.api.nvim_win_set_option(win_id, 'winblend', opt_winblend)
  vim.api.nvim_win_set_cursor(win_id, { screenpos.row, cursor_col })

  -- buffer-local variables so that we can access them later
  vim.api.nvim_buf_set_var(hint_buf_id, 'src_win_id', vim.api.nvim_get_current_win())
  vim.api.nvim_buf_set_var(hint_buf_id, 'win_top_line', win_top_line)
  vim.api.nvim_buf_set_var(hint_buf_id, 'buf_width', buf_width)
  vim.api.nvim_buf_set_var(hint_buf_id, 'buf_height', buf_height)
  vim.api.nvim_buf_set_var(hint_buf_id, 'per_line_words', per_line_words)

  -- keybindings
  create_jump_keymap(hint_buf_id, opt_keys)
end

-- Refine hints of the current buffer.
--
-- If the key doesn’t end up refining anything, TODO.
function M:refine_hints(key)
  local word, words = reduce_words(vim.b.per_line_words, key)

  if word == nil then
    vim.api.nvim_buf_set_var(0, 'per_line_words', words)
    update_hint_buffer(0, vim.b.buf_width, vim.b.buf_height, words)
  else
    local win_top_line = vim.b.win_top_line

    -- TODO: refactor this into its own function
    vim.api.nvim_buf_delete(0, {})

    -- JUMP!
    vim.api.nvim_win_set_cursor(0, { win_top_line + word.line, word.col - 1})
  end
end

return M

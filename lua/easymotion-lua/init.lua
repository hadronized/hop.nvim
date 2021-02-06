-- Options.
local opt_winblend = 50
local opt_keys = 'etisuranvdplqxgyhfmjzwk'

local hint_buf_id = nil
local M = {}

-- Create the keymap based on the input keys.
local function create_jump_keymap(buf_id, keys)
  -- remap all the jump keys
  for i = 1, #keys do
    vim.api.nvim_buf_set_keymap(buf_id, '', keys:sub(i, i), '<cmd>echo "deleted ' .. keys:sub(i, i) .. '"<cr>', { nowait = true })
  end

  vim.api.nvim_buf_set_keymap(buf_it, '', '<esc>', '<cmd>q<cr>', {})
  vim.api.nvim_buf_set_keymap(buf_id, '', 't', '<cmd>lua require"./lua/easymotion-lua/init".test()<cr>', {})
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

local function next_perm(keys, perm)
  local perm_size = #perm
  for i = perm_size, 1, -1 do
    local key = next_key(keys, perm[i])

    if key then
      perm[i] = key

      return perm
    else
      perm[i] = first_key(keys)
    end
  end

  perm[perm_size + 1] = first_key(keys)

  return perm
end

-- Get the first N permutations for a given set of keys.
--
-- Permutations are sorted by dimensions, so you will get 1-perm first, then 2-perm, 3-perm, etc. depending on the size
-- of the keys.
local function permutations(keys, n)
  local perms = {}
  local perm = {}

  for _ = 1, n do
    perm = next_perm(keys, perm)
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
  if hint[1] ~= key or hint:len() == 1 then
    return nil
  end

  return hint:sub(2)
end

-- Reduce all words’ hints and return the word for which the hint is fully reduced, if any.
local function reduce_words(words, key)
  local output = {}

  for _, word in pairs(words) do
    word.hint = reduce_hint(word.hint, key)

    if word.hint:len() == 1 then
      return word
    end

    output[#output + 1] = word
  end

  return nil, output
end

function M:test()
  print(vim.b.foo)
end

function M:open_hint_window()
  local buf_id = 0
  local win_view = vim.fn.winsaveview()
  local cursor_line = win_view['lnum']
  local cursor_col = win_view['col']
  local win_top_line = win_view['topline'] - 1
  local screenpos = vim.fn.screenpos(0, cursor_line, 0)
  local cursor_pos = { screenpos.row, cursor_col }
  local buf_width = vim.api.nvim_win_get_width(buf_id) - screenpos.col + 1
  local buf_height = vim.api.nvim_win_get_height(buf_id)
  local win_lines = vim.api.nvim_buf_get_lines(buf_id, win_top_line, win_top_line + buf_height, true)


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
  table.sort(indirect_words, function (a, b) return a.dist < b.dist end)

  -- generate permutations and update the lines with hints
  local hints = permutations(opt_keys, #indirect_words)
  for i, indirect in pairs(indirect_words) do
    per_line_words[indirect.i][indirect.j].hint = tbl_to_str(hints[i])
  end

  -- create a new buffer to contain the hints
  hint_buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_var(hint_buf_id, 'foo', 'test')

  -- fill the hint buffer with spaces
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

  -- keybindings
  create_jump_keymap(hint_buf_id, opt_keys)
end

return M

local M = {}

-- Get the first key of a key set.
local function first_key(keys)
  local n = keys:sub(1, vim.fn.byteidx(keys, 1))
  return keys:sub(1, vim.fn.byteidx(keys, 1))
end

-- Get the next key of the input key in the input key set, if any, or return nil.
local function next_key(keys, key)
  local i, e = keys:find(key)

  if e == #keys then
    return nil
  end

  local next = keys:sub(e + 1)
  local n = next:sub(1, vim.fn.byteidx(next, 1))
  return n
end

-- Permutation algorithm based on the “terminal / sequence keys sub-sets” method.
M.TermSeqBias = {}

-- Generate the next permutation.
--
-- term_keys is the terminal key set, seq_keys is the sequence key set and perm is the permutation for which we want
-- the next one.
--
-- The way this works is by incrementing a permutation as long it its terminal key has a next available key. A sequence
-- key is a key in the last ¼ part of the initial key set. For instance, for keys = "abcdefghijklmnop", "mnop" is the
-- last ¼ part, so those keys will be used as sequence keys. The invariant is that, terminal sequences cannot share
-- their last key with non-terminal sequences on the same level. The following are then not possible (given the example
-- keys from above):
--
-- - "a", "ab": not possible because even though "b" is okay, "a" is terminal for the first sequence, so it cannot be
--   used in the second.
-- - "a", "ma", "mb", mc": okay, as "a" is not shared on the same level.
-- - "pnac": without even going any further, this sequence is not possible as "a" is only used in terminal sequences, so
--   this "pnac" sequence would collide with the correct "pna" sequence.
--
-- Yet an another – easier – way to picture the idea is that any key from the terminal key set can only appear at the end
-- of sequence, and any key from the sequence key set can only appear before a terminal key in a sequence.
function M.TermSeqBias:next_perm(term_keys, seq_keys, perm)
  local perm_len = #perm

  if perm_len == 0 then
    return { first_key(term_keys) }
  end

  -- try to increment the terminal key; if it’s possible, then we can directly return the permutation as it’s the next
  -- one
  local term_key = next_key(term_keys, perm[perm_len])

  if term_key then
    perm[perm_len] = term_key

    return perm
  end

  -- perm was the last permutation for the current sequence keys, so we need to backtrack and increment sequence keys
  -- until one of them has a successor
  for i = perm_len - 1, 1, -1 do
    -- increment the sequence key; if it’s possible, then we have found the next permutation
    local seq_key = next_key(seq_keys, perm[i])

    if seq_key then
      -- set the terminal key to the first terminal key as we’re starting a new sequence
      perm[perm_len] = first_key(term_keys)
      perm[i] = seq_key

      return perm
    else
      -- the current sequence key doesn’t have a successor, so we set it back to the first sequence key because we will
      -- start a new sequence key either incrementing a parent of the current sequence key, or we will make a complete
      -- new permutation by incrementing its dimension
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
-- Permutations are sorted by dimensions, so you will get 1-perm first, then 2-perm, 3-perm, etc. depending on the size
-- of the keys.
function M.TermSeqBias:permutations(keys, n, opts)
  local quarter = #keys * opts.term_seq_bias
  local term_keys = keys:sub(1, quarter)
  local seq_keys = keys:sub(quarter + 1)
  local perms = {}
  local perm = {}

  for _ = 1, n do
    perm = self:next_perm(term_keys, seq_keys, perm)
    perms[#perms + 1] = vim.deepcopy(perm)
  end

  return perms
end

-- Permutation algorithm based on tries and backtrack filling.
M.TrieBacktrackFilling = {}

-- Get the sequence encoded in a trie by a pointer.
function M.TrieBacktrackFilling:lookup_seq_trie(trie, p)
  local seq = {}
  local t = trie

  for _, i in pairs(p) do
    local current_trie = t[i]

    seq[#seq + 1] = current_trie.key
    t = current_trie.trie
  end

  seq[#seq + 1] = t[#t].key

  return seq
end

-- Add a new permutation to the trie at the current pointer by adding a key.
function M.TrieBacktrackFilling:add_trie_key(trie, p, key)
  local seq = {}
  local t = trie

  -- find the parent trie
  for _, i in pairs(p) do
    local current_trie = t[i]

    seq[#seq + 1] = current_trie.key
    t = current_trie.trie
  end

  t[#t + 1] = { key = key; trie = {} }

  return trie
end

-- Maintain a trie pointer of a given dimension.
--
-- If a pointer has components { 4, 1 } and the dimension is 4, this function will automatically complete the missing
-- dimensions by adding the last index, i.e. { 4, 1, X, X }.
local function maintain_deep_pointer(depth, n, p)
  local q = vim.deepcopy(p)

  for i = #p + 1, depth do
    q[i] = n
  end

  return q
end

-- Generate the next permutation with backtrack filling.
--
-- - `keys` is the input key set.
-- - `trie` is a trie representing all the already generated permutations.
-- - `p` is the current pointer in the trie. It is a list of indices representing the parent layer in which the current
--   sequence occurs in.
--
-- Returns `perms` added with the next permutation.
function M.TrieBacktrackFilling:next_perm(keys, trie, p)
  if #trie == 0 then
    return { { key = first_key(keys); trie = {} } }, p
  end

  -- check whether the current sequence can have a next one
  local current_seq = self:lookup_seq_trie(trie, p)
  local key = next_key(keys, current_seq[#current_seq])

  if key ~= nil then
    -- we can generate the next permutation by just adding key to the current trie
    self:add_trie_key(trie, p, key)
    return trie, p
  else
    -- we have to backtrack; first, decrement the pointer if possible
    local max_depth = #p
    local keys_len = vim.fn.strwidth(keys)

    while #p > 0 do
      local last_index = p[#p]
      if last_index > 1 then
        p[#p] = last_index - 1

        p = maintain_deep_pointer(max_depth, keys_len, p)

        -- insert the first key at the new pointer after mutating the one already there
        self:add_trie_key(trie, p, first_key(keys))
        self:add_trie_key(trie, p, next_key(keys, first_key(keys)))
        return trie, p
      else
        -- we have exhausted all the permutations for the current layer; drop the layer index and try again
        p[#p] = nil
      end
    end

    -- all layers are completely full everywhere; add a new layer at the end
    p = maintain_deep_pointer(max_depth, keys_len, p)

    p[#p + 1] = #trie -- new layer
    self:add_trie_key(trie, p, first_key(keys))
    self:add_trie_key(trie, p, next_key(keys, first_key(keys)))

    return trie, p
  end
end

function M.TrieBacktrackFilling:trie_to_perms(trie, perm)
  local perms = {}
  local p = vim.deepcopy(perm)
  p[#p + 1] = trie.key

  if #trie.trie > 0 then
    for _, sub_trie in pairs(trie.trie) do
      vim.list_extend(perms, self:trie_to_perms(sub_trie, p))
    end
  else
    perms = { p }
  end

  return perms
end

function M.TrieBacktrackFilling:permutations(keys, n)
  local perms = {}
  local trie = {}
  local p = {}

  for _ = 1, n do
    trie, p = self:next_perm(keys, trie, p)
  end

  for _, sub_trie in pairs(trie) do
    vim.list_extend(perms, self:trie_to_perms(sub_trie, {}))
  end

  return perms
end

function M.permutations(keys, n, opts)
  return opts.perm_method:permutations(keys, n, opts)
end

return M

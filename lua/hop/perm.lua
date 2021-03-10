local M = {}

-- Get the first key of a key set.
local function first_key(keys)
  return keys:sub(1, 1)
end

-- Get the next key of the input key in the input key set, if any, or return nil.
local function next_key(keys, key)
  local i = keys:find(key)

  if i == #keys then
    return nil
  end

  local i1 = i + 1
  return keys:sub(i1, i1)
end

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
local function next_perm(term_keys, seq_keys, perm)
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
function M.permutations(keys, n, opts)
  local quarter = #keys * opts.term_seq_bias
  local term_keys = keys:sub(1, quarter)
  local seq_keys = keys:sub(quarter + 1)
  local perms = {}
  local perm = {}

  for _ = 1, n do
    perm = next_perm(term_keys, seq_keys, perm)
    perms[#perms + 1] = vim.deepcopy(perm)
  end

  return perms
end

return M

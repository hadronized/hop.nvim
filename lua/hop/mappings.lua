local M = {}

-- Checkout mappings with the chars of pattern as key
function M.checkout(pat, opts)
  local dict_pat = ''

  for k = 1, #pat do
    local char = pat:sub(k, k)
    local dict_char_pat = ''
    -- checkout dict-char pattern from each mapping dict
    for _, v in ipairs(opts.match_mappings) do
      local val = opts.match_mappings[v][char]
      if val ~= nil then
        dict_char_pat = dict_char_pat .. val
      end
    end

    if dict_char_pat == '' then
      dict_pat = dict_pat .. char
    else
      dict_pat = dict_pat .. '[' .. dict_char_pat .. ']'
    end
  end

  return dict_pat
end

return M

local M = {}

---@alias HintDirection "require'hop.constants'.HintDirection.BEFORE_CURSOR"|"require'hop.constants'.HintDirection.AFTER_CURSOR"

M.HintDirection = {
  BEFORE_CURSOR = 1,
  AFTER_CURSOR = 2,
}

---@alias HintLineException "require'hop.constants'.HintLineException.EMPTY_LINE"|"require'hop.constants'.HintLineException.INVALID_LINE"

M.HintLineException = {
  EMPTY_LINE = -1, -- Empty line: match hint pattern when col_offset = 0
  INVALID_LINE = -2, -- Invalid line: no need to match hint pattern
}

-- Magic constants for highlight priorities;
--
-- Priorities are ranged on 16-bit integers; 0 is the least priority and 2^16 - 1 is the higher.
-- We want Hop to override everything so we use a very high priority for grey (2^16 - 3 = 65533); hint
-- priorities are one level above (2^16 - 2) and the virtual cursor one level higher (2^16 - 1), which
-- is the higher.

M.GREY_PRIO = 65533
M.HINT_PRIO = 65534
M.CURSOR_PRIO = 65535

return M

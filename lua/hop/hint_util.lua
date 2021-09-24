local constants = require'hop.constants'

local M = {}
-- Create hint lines from each windows to complete `hint_states` data
local function create_hint_winlines(hs, direction)
  -- get a bunch of information about the window and the cursor
  local hwin = hs.hwin
  local cursor_pos = hs.cursor_pos
  vim.api.nvim_set_current_win(hwin)
  vim.api.nvim_win_set_cursor(hwin, cursor_pos)
  local win_view = vim.fn.winsaveview()
  local win_info = vim.fn.getwininfo(hwin)[1]
  local top_line = win_info.topline - 1 -- `getwininfo` use 1-based line number
  local bot_line = win_info.botline - 1 -- `getwininfo` use 1-based line number

  -- adjust the visible part of the buffer to hint based on the direction
  local direction_mode = nil
  if direction == constants.HintDirection.BEFORE_CURSOR then
    bot_line = cursor_pos[1] - 1 -- `nvim_win_get_cursor()` use 1-based line number
    direction_mode = { cursor_col = cursor_pos[2], direction = direction }
  elseif direction == constants.HintDirection.AFTER_CURSOR then
    top_line = cursor_pos[1] - 1 -- `nvim_win_get_cursor()` use 1-based line number
    direction_mode = { cursor_col = cursor_pos[2], direction = direction }
  end
  hs.dir_mode = direction_mode

  -- NOTE: due to an (unknown yet) bug in neovim, the sign_width is not correctly reported when shifting the window
  -- view inside a non-wrap window, so we can’t rely on this; for this reason, we have to implement a weird hack that
  -- is going to disable the signs while hop is running (I’m sorry); the state is restored after jump
  -- local left_col_offset = win_info.variables.context.number_width + win_info.variables.context.sign_width
  -- hack to get the left column offset in nowrap

  -- 0-based cell index of the leftmost visible character
  local win_leftcol = win_view.leftcol
  -- 0-based cell index of the rightmost visible character if nowrap, nil otherwise
  local win_rightcol = nil
  if not vim.wo.wrap then
    vim.api.nvim_win_set_cursor(hwin, { cursor_pos[1], 0 })
    local true_width = (win_info.width - (vim.fn.wincol() - 1))
    win_rightcol = win_leftcol + true_width - 1
    vim.fn.winrestview(win_view)
  end

  -- get the buffer lines
  -- this line number
  hs.lnums = {}
  -- 0-based byte index of the leftmost character in this line
  hs.lcols = {}
  -- this line string
  hs.lines = {}
  local lnr = top_line
  while lnr <= bot_line do
      table.insert(hs.lnums, lnr)
      local fold_end = vim.fn.foldclosedend(lnr + 1) -- `foldclosedend()` use 1-based line number
      if fold_end == -1 then
        -- save line number and sliced line text to hint
        local cur_line = vim.fn.getline(lnr + 1) -- `getline()` use 1-based line number
        local cur_cols = 0
        -- 0-based cell index of last character in cur_line
        local last_idx = vim.api.nvim_strwidth(cur_line) - 1
        if win_rightcol then
          if win_leftcol > last_idx then
            -- constants.HintLineException.EMPTY_LINE means empty line and only col=1 can jump to
            cur_cols = -1
            cur_line = constants.HintLineException.EMPTY_LINE
          else
            -- 0-based byte index of leftmost visible character in line
            local cidx0 = vim.fn.byteidx(cur_line, win_leftcol)
            -- 0-based byte index of rightmost visible character in line
            local cidx1 = win_rightcol <= last_idx
              and vim.fn.byteidx(cur_line, win_rightcol) or vim.fn.byteidx(cur_line, last_idx)
            cur_cols = cidx0
            cur_line = cur_line:sub(cidx0 + 1, cidx1 + 1)
          end
        end

        -- adjust line and start col for direction
        if lnr == top_line then
          if direction_mode and direction == constants.HintDirection.AFTER_CURSOR then
            local start_col = direction_mode.cursor_col
            local new_offset = start_col - cur_cols
            if new_offset > 0 then
              cur_line = cur_line:sub(new_offset + 1)
              cur_cols = start_col
            end
          end
        elseif lnr == bot_line then
          if direction_mode and direction == constants.HintDirection.BEFORE_CURSOR then
            local end_col = direction_mode.cursor_col
            local new_offset = end_col - cur_cols
            if new_offset >= 0 then
              cur_line = cur_line:sub(1, new_offset)
            end
          end
        end
        table.insert(hs.lcols, cur_cols)
        table.insert(hs.lines, cur_line)
        lnr = lnr + 1
      else
        -- skip fold lines and only col=1 can jump to at fold lines
        table.insert(hs.lcols, -1)
        table.insert(hs.lines, constants.HintLineException.EMPTY_LINE)
        lnr = fold_end
      end
  end
end

-- Crop duplicated hint lines area  from `hc` compared with `hp`
local function crop_winlines(hc, hp)
  if hc.lnums[#hc.lnums] < hp.lnums[1] or hc.lnums[1] > hp.lnums[#hp.lnums] then
    return
  end

  local ci = 1         -- start line index of hc
  local ce = #hc.lnums -- end line index of hc
  local pi = 1         -- start line index of hp
  local pe = #hp.lnums -- end line index of hp

  while ci <= ce and pi <= pe do
    if hc.lnums[ci] < hp.lnums[pi] then
      ci = ci + 1
    elseif hc.lnums[ci] > hp.lnums[pi] then
      pi = pi + 1
    elseif hc.lnums[ci] == hp.lnums[pi] then
      if (hc.lines[ci] == constants.HintLineException.INVALID_LINE) or
         (hp.lines[pi] == constants.HintLineException.INVALID_LINE) then
         goto next
      end
      if (type(hc.lines[ci]) == "string") and (type(hp.lines[pi]) == "string") then
        local cl = hc.lcols[ci]       -- leftmost 0-based byte index of ci line
        local cr = cl + #hc.lines[ci] - 1 -- rightmost 0-based byte index of ci line
        local pl = hp.lcols[pi]       -- leftmost 0-based byte index of pi line
        local pr = pl + #hp.lines[pi] - 1 -- rightmost 0-based byte index of pi line

        if cl > pr or cr < pl then
          -- Must keep this empty block to guarantee other elseif-condition correct
          -- Must compare cl-pl prior than cl-pr at elseif-condition
        elseif cl <= pl and cr <= pr then
          -- p:    ******
          -- c: ******
          hc.lines[ci] = string.sub(hc.lines[ci], 1, pl - cl)
        elseif cl <= pl and cr >= pr then
          -- p:    ******
          -- c: ************
          hp.lines[pi] = hc.lines[ci]
          hp.lcols[pi] = hc.lcols[ci]
          hc.lines[ci] = constants.HintLineException.INVALID_LINE
        elseif cl <= pr and cr >= pr then
          -- p: ******
          -- c:    ******
          hc.lcols[ci] = pr + 1
          hc.lines[ci] = string.sub(hc.lines[ci], pr - cl + 2)
        elseif cl <= pr and cr <= pr then
          -- p: ************
          -- c:    ******
          hc.lines[ci] = constants.HintLineException.INVALID_LINE
        end
      elseif (hc.lines[ci] == constants.HintLineException.EMPTY_LINE) and
             (hp.lines[pi] == constants.HintLineException.EMPTY_LINE) then
          hc.lines[ci] = constants.HintLineException.INVALID_LINE
      end

      ::next::
      ci = ci + 1
      pi = pi + 1
    end
  end
end

-- Create hint lines from each buffer to complete `hint_states` data
local function create_hint_buflines(hh, direction)
  for _, hs in ipairs(hh) do
    create_hint_winlines(hs, direction)
  end

  -- Remove inter-covered area of different windows with same buffer.
  -- Iterate reverse to guarantee the first window has the max area.
  for c = #hh, 1, -1 do
    for p = 1, c-1 do
      crop_winlines(hh[c], hh[p])
    end
  end
end

-- Create all hint state for all multi-windows.
-- Specification for `hint_states`:
--{
--   { -- hist state list that each contains one buffer
--      hbuf = <buf-handle>,
--      { -- windows list that display the same buffer
--         hwin = <win-handle>,
--         cursor_pos = { }, -- byte-based column
--         dir_mode = { },
--         lnums = { }, -- line number is 0-based
--         lcols = { }, -- byte-based column offset of each line
--         lines = { }, -- context to match hint of each line
--      },
--      ...
--   },
--   ...
--}
--
-- Some confusing column:
--   byte-based column: #line, strlen(), col(), getpos(), getcurpos(), nvim_win_get_cursor(), winsaveview().col
--   cell-based column: strwidth(), strdisplaywidth(), nvim_strwidth(), wincol(), winsaveview().leftcol
-- Take attention on that nvim_buf_set_extmark() and vim.regex:match_str() use byte-based buffer column.
-- To get exactly what's showing in window, use strchars() and strcharpart() which can handle multi-byte characters.
function M.create_hint_states(multi_windows, direction)
  local hss = { } -- hint_states

  -- Current window as first item
  local cur_hwin = vim.api.nvim_get_current_win()
  local cur_hbuf = vim.api.nvim_win_get_buf(cur_hwin)
  hss[#hss + 1] = {
    hbuf = cur_hbuf,
    {
      hwin = cur_hwin,
      cursor_pos = vim.api.nvim_win_get_cursor(cur_hwin),
    }
  }

  -- Other windows of current tabpage
  if multi_windows then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local b = vim.api.nvim_win_get_buf(w)
      if w ~= cur_hwin then

        -- Check duplicated buffers
        local hh = nil
        for _, _hh in ipairs(hss) do
          if b == _hh.hbuf then
            hh = _hh
            break
          end
        end

        if hh then
          hh[#hh + 1] = {
            hwin = w,
            cursor_pos = vim.api.nvim_win_get_cursor(w),
          }
        else
          hss[#hss + 1] = {
            hbuf = b,
            {
              hwin = w,
              cursor_pos = vim.api.nvim_win_get_cursor(w),
            }
          }
        end

      end
    end
  end

  for _, hh in ipairs(hss) do
    create_hint_buflines(hh, direction)
  end

  vim.api.nvim_set_current_win(hss[1][1].hwin)

  return hss
end

function M.get_grey_out(hint_states)
  local grey_out = {}
  for _, hh in ipairs(hint_states) do
    local hl_buf_data = {}
    hl_buf_data.buf = hh.hbuf
    local ranges = {}
    hl_buf_data.ranges = ranges

    local function add_range(line, col_start, col_end)
      ranges[#ranges + 1] = {line = line, col_start = col_start, col_end = col_end}
    end

    for _, hs in ipairs(hh) do
      -- Highlight unmatched lines
      if hs.dir_mode ~= nil then
        if hs.dir_mode.direction == constants.HintDirection.AFTER_CURSOR then
          -- Hightlight lines after cursor
          add_range(hs.lnums[1], hs.dir_mode.cursor_col, -1)
          for k = 2, #hs.lnums do
            add_range(hs.lnums[k], 0, -1)
          end
        elseif hs.dir_mode.direction == constants.HintDirection.BEFORE_CURSOR then
          -- Hightlight lines before cursor
          for k = 1, #hs.lnums - 1 do
            add_range(hs.lnums[k], 0, -1)
          end
          add_range(hs.lnums[#hs.lnums], 0, hs.dir_mode.cursor_col)
        end
      else
        -- Hightlight all lines
        for _, lnr in ipairs(hs.lnums) do
          add_range(lnr, 0, -1)
        end
      end
    end

    grey_out[#grey_out + 1] = hl_buf_data
  end

  return grey_out
end

return M

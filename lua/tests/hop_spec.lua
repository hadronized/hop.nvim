local hop = require  'hop'
local hop_hint = require  'hop.hint'

local eq = assert.are.same

local function override_getchar(override, closure)
  local old_getchar = vim.fn.getchar
  vim.fn.getchar = override
  local r = closure()
  vim.fn.getchar = old_getchar
  return r
end

describe("Hop movement is correct", function()

  before_each(function()
    vim.cmd  [[
    bdelete!
    enew!
  ]]
    hop.setup()
  end)

  it("HopChar1AC", function()

    -- create new window, put cursor at the beginning
    -- TODO try erasing this / make it work with fewer lines
    local w = vim.api.nvim_open_win(0, true, {
      width = 60,
      height = 2,
      relative = "editor",
      row = 0,
      col = 0,
    })
    vim.api.nvim_win_set_cursor(w, {1, 1})

    -- add line, keep start position
    local start_pos = vim.fn.getcurpos()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz",
    })
    vim.fn.setpos(".", start_pos)

    -- do HopChar1AC, simulate user input
    local key_counter = 0
    override_getchar(function(...)
      key_counter = key_counter + 1
      if key_counter == 1 then
        return vim.fn.char2nr("c") -- hop to any of the two «c»
      end
      if key_counter == 2 then
        return vim.fn.char2nr("a") -- choose the first option
      end
      error  "this line is never reached"
    end, function()
      hop.hint_char1  {direction = hop_hint.HintDirection.AFTER_CURSOR}
    end)

    -- check that some letter is the first key
    local end_pos = vim.fn.getcurpos()
    local end_col = end_pos[3]
    eq(end_col, 3)
  end)
end)

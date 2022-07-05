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
  it("HopChar1AC", function()
    -- create temp buffer
    local b = vim.api.nvim_create_buf(false, true)

    -- create new window, put cursor at the beginning
    local w = vim.api.nvim_open_win(b, true, {
      width = 60,
      height = 2,
      relative = "editor",
      row = 0,
      col = 0,
    })
    vim.api.nvim_win_set_cursor(w, {1, 1})

    -- add line
    vim.api.nvim_buf_set_lines(b, 0, -1, false, {
      "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz",
    })

    -- put cursor at the beginning, just before hopping
    vim.api.nvim_win_set_cursor(w, {1, 1})
    local key_counter = 0

    -- do HopChar1AC, insert letter
    override_getchar(function(...)
      key_counter = key_counter + 1
      if key_counter == 1 then
        return "c" -- hop to any of the two «c»
      end
      if key_counter == 2 then
        return "a" -- choose the first option
      end
      error  "this line is never reached"
    end, function()
      hop.hint_char1  {direction = hop_hint.HintDirection.AFTER_CURSOR}
    end)
    -- check that some letter is the first key
    local _, _, c, _ = vim.fn.getcurpos()
    eq(c, 3)
  end)
end)

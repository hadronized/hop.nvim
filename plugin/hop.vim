if !has('nvim')
  echohl Error
  echom 'This plugin only works with Neovim'
  echohl clear
  finish
endif

" The jump-to-word command.
command! HopWord lua require'hop'.hint(require'hop.hint'.by_word_start())
command! HopWordBC lua require'hop'.hint(require'hop.hint'.by_word_start({ direction = require'hop.constants'.HintDirection.BEFORE_CURSOR }))
command! HopWordAC lua require'hop'.hint(require'hop.hint'.by_word_start({ direction = require'hop.constants'.HintDirection.AFTER_CURSOR }))
command! HopWordMW lua require'hop'.hint(require'hop.hint'.by_word_start({ multi_windows = true }))

" The jump-to-pattern command.
command! HopPattern lua require'hop'.hint(require'hop.hint'.by_any_pattern())
command! HopPatternBC lua require'hop'.hint(require'hop.hint'.by_any_pattern({ direction = require'hop.constants'.HintDirection.BEFORE_CURSOR }))
command! HopPatternAC lua require'hop'.hint(require'hop.hint'.by_any_pattern({ direction = require'hop.constants'.HintDirection.AFTER_CURSOR }))
command! HopPatternMW lua require'hop'.hint(require'hop.hint'.by_any_pattern({ multi_windows = true }))

" The jump-to-char-1 command.
command! HopChar1 lua require'hop'.hint(require'hop.hint'.by_char1_pattern())
command! HopChar1BC lua require'hop'.hint(require'hop.hint'.by_char1_pattern({ direction = require'hop.constants'.HintDirection.BEFORE_CURSOR }))
command! HopChar1AC lua require'hop'.hint(require'hop.hint'.by_char1_pattern({ direction = require'hop.constants'.HintDirection.AFTER_CURSOR }))
command! HopChar1MW lua require'hop'.hint(require'hop.hint'.by_char1_pattern({ multi_windows = true }))

" The jump-to-char-2 command.
command! HopChar2 lua require'hop'.hint(require'hop.hint'.by_char2_pattern())
command! HopChar2BC lua require'hop'.hint(require'hop.hint'.by_char2_pattern({ direction = require'hop.constants'.HintDirection.BEFORE_CURSOR }))
command! HopChar2AC lua require'hop'.hint(require'hop.hint'.by_char2_pattern({ direction = require'hop.constants'.HintDirection.AFTER_CURSOR }))
command! HopChar2MW lua require'hop'.hint(require'hop.hint'.by_char2_pattern({ multi_windows = true }))

" The jump-to-line command.
command! HopLine lua require'hop'.hint(require'hop.hint'.by_line_start())
command! HopLineBC lua require'hop'.hint(require'hop.hint'.by_line_start({ direction = require'hop.constants'.HintDirection.BEFORE_CURSOR }))
command! HopLineAC lua require'hop'.hint(require'hop.hint'.by_line_start({ direction = require'hop.constants'.HintDirection.AFTER_CURSOR }))
command! HopLineMW lua require'hop'.hint(require'hop.hint'.by_line_start({ multi_windows = true }))

" The jump-to-line command.
command! HopLineStart   lua require'hop'.hint(require'hop.hint'.by_line_start_skip_whitespace())
command! HopLineStartBC lua require'hop'.hint(require'hop.hint'.by_line_start({ direction = require'hop.constants'.HintDirection.BEFORE_CURSOR }))
command! HopLineStartAC lua require'hop'.hint(require'hop.hint'.by_line_start({ direction = require'hop.constants'.HintDirection.AFTER_CURSOR }))
command! HopLineStartMW lua require'hop'.hint(require'hop.hint'.by_line_start({ multi_windows = true }))

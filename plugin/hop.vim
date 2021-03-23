if !has('nvim')
  echohl Error
  echom 'This plugin only works with Neovim'
  echohl clear
  finish
endif

" The jump-to-word command.
command! HopWord lua require'hop'.hint_words()

" The jump-to-pattern command.
command! HopPattern lua require'hop'.hint_patterns()

" The jump-to-char-1 command.
command! HopChar1 lua require'hop'.hint_char1()

" The jump-to-char-2 command.
command! HopChar2 lua require'hop'.hint_char2()

" The jump-to-line command.
command! HopLine lua require'hop'.hint_lines()

command! HopLineDown lua require'hop'.hint_line_down()

command! HopLineUp lua require'hop'.hint_line_up()

command! HopWordAfter lua require'hop'.hint_word_after({same_line = true})

command! HopWordBefore lua require'hop'.hint_word_before({same_line = true})

command! HopWordAfterEnd lua require'hop'.hint_word_after_end({same_line = true})

command! HopWordBeforeEnd lua require'hop'.hint_word_before_end({same_line = true})

command! HopFind lua require'hop'.hint_find()

command! HopFindBefore lua require'hop'.hint_find_before()

command! HopFindTo lua require'hop'.hint_find_to()

command! HopFindToBefore lua require'hop'.hint_find_to_before()

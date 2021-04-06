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
command! HopChar1 lua require'hop'.hint_char1(ANYWHERE, false)

" The jump-to-char-2 command.
command! HopChar2 lua require'hop'.hint_char2()

" The jump-to-line command.
command! HopLine lua require'hop'.hint_lines()

command! HopLineDown lua require'hop'.hint_column_line(AFTER_CURSOR)

command! HopLineUp lua require'hop'.hint_column_line(BEFORE_CURSOR)

command! HopWordAfter lua require'hop'.hint_word(AFTER_CURSOR, true)

command! HopWordBefore lua require'hop'.hint_word(BEFORE_CURSOR, true)

command! HopWordEndAfter lua require'hop'.hint_word_end(AFTER_CURSOR, true)

command! HopWordEndBefore lua require'hop'.hint_word_end(BEFORE_CURSOR, true)

command! HopFind lua require'hop'.hint_char1(AFTER_CURSOR, true)

command! HopFindBefore lua require'hop'.hint_char1(BEFORE_CURSOR, true)

command! HopFindTo lua require'hop'.hint_char1_before(AFTER_CURSOR, true)

command! HopFindToBefore lua require'hop'.hint_char1_after(BEFORE_CURSOR, true)

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
command! HopChar1 lua require'hop'.hint_char1('anywhere', false)

" The jump-to-char-2 command.
command! HopChar2 lua require'hop'.hint_char2()

" The jump-to-line command.
command! HopLine lua require'hop'.hint_lines()

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

command! HopJ lua require'hop'.hint_j()

command! HopK lua require'hop'.hint_k()

command! HopWordLine lua require'hop'.hint_words({same_line = true})

command! HopW lua require'hop'.hint_w({same_line = true})

command! HopB lua require'hop'.hint_b({same_line = true})

command! HopE lua require'hop'.hint_e({same_line = true})

command! HopGE lua require'hop'.hint_ge({same_line = true})

command! HopF lua require'hop'.hint_f()

command! HopFF lua require'hop'.hint_F()

command! HopT lua require'hop'.hint_t()

command! HopTT lua require'hop'.hint_T()

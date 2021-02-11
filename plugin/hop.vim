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

" Highlight used for the mono-sequence keys (i.e. sequence of 1).
highlight default HopNextKey  guifg=#ff007c gui=bold blend=0

" Highlight used for the first key in a sequence.
highlight default HopNextKey1 guifg=#00dfff gui=bold blend=0

" Highlight used for the second and remaining keys in a sequence.
highlight default HopNextKey2 guifg=#2b8db3          blend=0

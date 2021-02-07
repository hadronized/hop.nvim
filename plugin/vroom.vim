if !has('nvim')
  echohl Error
  echom 'This plugin only works with Neovim'
  echohl clear
  finish
endif

" The jump-to-word command.
command! VroomWord lua require'vroom'.jump_words()

" Highlight used for the mono-sequence keys (i.e. sequence of 1).
highlight default VroomNextKey  guifg=#e0115f gui=bold blend=0

" Highlight used for the first key in a sequence.
highlight default VroomNextKey1 guifg=#00dfff gui=bold blend=0

" Highlight used for the second and remaining keys in a sequence.
highlight default VroomNextKey2 guifg=#00B8FF          blend=0

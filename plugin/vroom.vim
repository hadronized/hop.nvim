if !has('nvim')
  echohl Error
  echom 'This plugin only works with Neovim'
  echohl clear
  finish
endif

" 
highlight default VroomNextKey  guifg=#e0115f gui=bold blend=0
highlight default VroomNextKey1 guifg=#00dfff gui=bold blend=0
highlight default VroomNextKey2 guifg=#00B8FF          blend=0

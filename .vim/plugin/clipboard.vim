" Use vim's system clipboard register ("*) instead of the unnamed register for
" yank/put/delete. This links these commands to the system clipboard
if !has('clipboard') && !has('xterm_clipboard')
  echom "[VIMRC] WARNING: Not compiled with clipboard support"
endif
set clipboard=unnamed

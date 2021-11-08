" Persistent undo: keep undo history across sessions - store in XDG_CACHE (?)
if has('persistent_undo')
  " Make sure you have created the '~/.cache/vim-undodir' directory.
  let &undodir = expand('$HOME/.cache/vim-undodir')
  set undofile
endif

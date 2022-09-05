if has('nvim')
  " nvim does this automatically. And in fact, it will even change your cursor
  " for 'operator pending' mode! Which I don't belive vim can do.
  finish
endif

" https://github.com/khuedoan/dotfiles/blob/97d5d7bb4f00374a19beb50eaa75a83a7d570b06/.vimrc#L48
" Change cursor shape in different modes (see :help cursor-shape)
"
" *termcap-cursor-shape*

" START INSERT: '|'
let &t_SI = "[5 q"

" START REPLACE: '_'
let &t_SR = "[3 q"

" END   INSERT: '█'
let &t_EI = "[2 q"

" Enter Insert  : 't_SI'
" Enter Replace : 't_SR'
" Leaving Insert or Replace 't_EI' is used.

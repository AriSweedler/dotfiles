" https://github.com/khuedoan/dotfiles/blob/97d5d7bb4f00374a19beb50eaa75a83a7d570b06/.vimrc#L48
" Change cursor shape in different modes (see :help cursor-shape)
"
" *termcap-cursor-shape*

" START INSERT: |
let &t_SI = "[5 q"

" START REPLACE: <TODO>
let &t_SR = "[3 q"
" END   INSERT: █
let &t_EI = "[2 q"

" Enter Insert : 't_SI'
" Enter Replace: 't_SR'
" Leaving Insert or Replace 't_EI' is used.

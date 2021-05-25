setlocal tabstop=4 expandtab
setlocal cindent foldmethod=syntax textwidth=120
setlocal foldlevel=10

" Print a line of a var's value
command! -nargs=1 DebugP :normal ostd::cout << "<args> = " << <args> << std::endl;

" Easily open a corresponding heaheader/cpp file
nnoremap <Leader>head :vsp %:r.h<CR>
nnoremap <Leader>cpp :vsp %:r.cpp<CR>

" Make a function header signature from a constructor
let @c = "0f:xxdB$dF:xdF)==A);gqq"
" Make a function header signature from a function declaration
let @h = "0f f:xxdB==A;gqq"

setlocal cursorline

" Experimental...
let &makeprg='docker run --mount type=bind,source="$HOME/Desktop/source",destination="$HOME/Desktop/source" ari-build-image'
setlocal errorformat=%f:%l:%c:\ %trror:\ %m
setlocal errorformat+=\|\|\ %f:%l:%c:\ note:\ %m
nnoremap <Leader>m :lmake<CR>
" TODO add %E for multiline

nnoremap <silent> <Leader>gq mqgggqG`q:delmark q<CR>zz

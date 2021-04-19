setlocal tabstop=4 expandtab
setlocal cindent foldmethod=syntax textwidth=120
set foldlevel=10

" Print a line of a var's value
command! -nargs=1 DebugP :normal ostd::cout << "<args> = " << <args> << std::endl;

" Easily open a corresponding heaheader/cpp file
nnoremap <Leader>head :vsp %:r.h<CR>
nnoremap <Leader>cpp :vsp %:r.cpp<CR>

" Make a function header signature from a constructor
let @c = "0f:xxdB$dF:xdF)==A);gqq"
" Make a function header signature from a function declaration
let @h = "0f f:xxdB==A;gqq"

set cursorline

" Experimental...
let &makeprg="remote-build venPlatformHandler u16 default"
set errorformat=%f:%l:%c:\ %trror:\ %m
nnoremap <Leader>m :lmake<CR>
" TODO add %E for multiline

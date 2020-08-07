setlocal tabstop=4 softtabstop=4 shiftwidth=4 expandtab
setlocal cindent foldmethod=syntax textwidth=128
set foldmethod=syntax

" Print a line of a var's value
command! -nargs=1 DebugP :normal ostd::cout << "<args> = " << <args> << std::endl;

" Open a cpp file and it's h file in a new tab
" TODO how can I make this local?
command! -nargs=1 TabeC :tabe <args>.cpp <Bar> :vsp <args>.h

" Easily open a corresponding heaheader/cpp file
nnoremap <Leader>head :vsp %:r.h<CR>
nnoremap <Leader>cpp :vsp %:r.cpp<CR>

" Make a function header signature from a constructor
let @c = "0f:xxdB$dF:xdF)==A);gqq"
" Make a function header signature from a function declaration
let @h = "0f f:xxdB==A;gqq"

set cursorline

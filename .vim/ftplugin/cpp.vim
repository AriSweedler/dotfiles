setlocal tabstop=2 softtabstop=2 shiftwidth=2 expandtab
setlocal cindent foldmethod=syntax textwidth=80

" Print a line of a var's value
command! -nargs=1 DebugP :normal ostd::cout << "<args> = " << <args> << std::endl;

" Open a cpp file and it's h file in a new tab
" TODO how can I make this local?
command! -nargs=1 TabeC :tabe <args>.cpp <Bar> :vsp <args>.h

" Make a function header signature from a constructor
let @c = "0f:xxdb==A;gqq"
" Make a function header signature from a function declaration
let @h = "0f f:xxdb==A;gqq"

" Run make check in the other window real quick
let @m="^W^Wmake check^M^W^W"

setlocal tabstop=4 expandtab
setlocal autoindent foldmethod=indent

" TODO make a 'format everything' keybinding. This is the implementation for here
nnoremap <buffer> <Leader>= :!python3 -m black %<CR>L

" TODO make a 'search for ARI DEBUG' keybinding. This is the implementation for here
nnoremap <buffer> <Leader>A /print(f"\zs\[ARI\]<CR>
iabbrev loggy print(f"[ARI]")<C-o>F"

" TODO convert any string into an f-string. Currently buggy (Should just use a function)
nnoremap <buffer> <Leader>f 0da"0f(af<C-c>p

" Run the current file as a python file with <Leader>m
nnoremap <buffer> <Leader>m :!python3 %<CR>

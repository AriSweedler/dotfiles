setlocal tabstop=2 expandtab
setlocal nospell

setlocal foldmethod=marker

" Easily search for Leader mappings
map <buffer> <Leader>/<Leader> /\c.Leader><CR>

nnoremap <buffer> <Leader>f 0xx$xxA {{{<C-c>
nnoremap <buffer> <Leader>F 0xx$xxA }}}<C-c>

" Debugging
" TODO another thing to standardize.
" * loggy
" * <Leader>m
" * Format this file
iabbrev loggy echom "[ARI] -"<Left>

syntax keyword vimIfError fi
highlight link vimIfError Error

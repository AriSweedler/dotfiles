setlocal tabstop=2 expandtab

" If I have a bunch of functions, this is helpful.
setlocal foldmethod=manual
nnoremap <buffer> <Leader>zM :g/() {$/norm $zfaB<CR>

" TODO figure out how to configure `matchit` to properly jump aroun syntax

setlocal tabstop=2 expandtab

" If I have a bunch of functions, this is helpful.
setlocal foldmethod=manual
nnoremap <buffer> <Leader>zM :g/() {$/norm $zfaB<CR>

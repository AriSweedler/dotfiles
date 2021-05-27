setlocal tabstop=2 expandtab

" Fold all functions
setlocal foldmethod=manual
nnoremap <buffer> <Leader>zM :g/() {$/norm $zfaB<CR>

" TODO maybe <Leader>m should get generalized, too.
" Use shellcheck to lint easily
nnoremap <buffer> <Leader>m :lmake<CR>
setlocal makeprg=shellcheck\ -x\ %
setlocal errorformat=In\ %f\ line\ %l:

" TODO figure out how to configure `matchit` to properly jump around syntax

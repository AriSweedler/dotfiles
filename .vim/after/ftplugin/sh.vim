setlocal tabstop=2 expandtab
setlocal foldlevel=0
setlocal autoindent

" Have bash syntax fold stuff nicely. Because they don't want that by default.
"
" Lmfao... some old dudes wrote this and they didn't wanna use 3 variables. So
" they use a friggin bitfield. In a SCRIPTING language. Insane xD
let g:sh_fold_enabled = 1 + 2 + 4

" On unknown `*.sh` files, assume it's bash.
let g:is_bash = 1

" TODO maybe <Leader>m should get generalized, too.
" Use shellcheck to lint easily
nnoremap <buffer> <Leader>m :lmake<CR>
setlocal makeprg=shellcheck\ -x\ %
setlocal errorformat=In\ %f\ line\ %l:

" TODO figure out how to configure `matchit` to properly jump around syntax

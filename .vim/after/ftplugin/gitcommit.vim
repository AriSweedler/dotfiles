runtime after/ftplugin/text.vim

setlocal tabstop=2 expandtab
setlocal textwidth=72 autoindent
setlocal comments=fb:* formatoptions+=n
setlocal foldmethod=marker foldlevel=1
setlocal spell

" highlight columns
let &colorcolumn="50,72"

nnoremap <Leader>S o* skiptests<C-c>:w<CR>

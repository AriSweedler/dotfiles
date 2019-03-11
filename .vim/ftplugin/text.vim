setlocal tabstop=2 softtabstop=2 shiftwidth=2 expandtab
setlocal foldmethod=syntax textwidth=80
setlocal spell autoindent

setlocal comments=""

highlight DoubleSpace ctermbg=6
match DoubleSpace /[^ ]\zs  \ze[^ *]/

let @f = 'cgn '
nnoremap <silent> <leader>f /[^ ]\zs  \ze[^ *]<CR>999@f
"TODO how to not clobber the @/ register? Maybe 'q/<UP><CR>?

"TODO a macro to wrap a visual block of text in an ascii box?

setlocal tabstop=2 softtabstop=2 shiftwidth=2 expandtab
setlocal foldmethod=syntax textwidth=80
setlocal spell autoindent virtualedit=all

setlocal comments="bf:*"

highlight DoubleSpace ctermbg=6
match DoubleSpace /[^ ]\zs  \ze[^ *]/

" Would this work as
" let @f = 'x'
let @f = 'cgn '
nnoremap <silent> <leader>f /[^ ]\zs  \ze[^ *]<CR>999@f

" TODO upgrade the thing to not clobber the search register
"nnoremap <silent> <leader>f :call RemoveDoubleSpace()<CR>
function RemoveDoubleSpace()
  " Save the search register
  let saveSearch=@/ " TODO how to dereference register

  " TODO Do the operation on the regex
  /[^ ]\zs  \ze[^ *]<CR>999@f

  " Restore the search register
  let @/=l:saveSearch " TODO how to set register
endfunction

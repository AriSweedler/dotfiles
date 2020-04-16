""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
call ChangeTextWidth(45)
set ts=2 sts=2 sw=2 et

function! DumpSlatty()
  put =&comments
  put =&autoindent
  put =&formatoptions
  put =&formatlistpat
endfunction
command DumpSlatt source /Users/ari/.vim/after/ftplugin/test.vim <Bar> call DumpSlatty()

iabbrev a abc
inoremap b abc 123 4 56 789 101112
nnoremap <Leader>1 "bp:DumpSlatt<CR>"ap<Leader>sf
"""""""""""""""""""""""""""""" Playing with stuff """"""""""""""""""""""""""""""
set comments&
set formatoptions&
set formatlistpat&

set comments=fb:*
set autoindent
set formatoptions=tcqj
set formatlistpat=^\\s*[-*+]\\s\\+\\ze\\S


" Indent settings
setlocal tabstop=2 shiftwidth=2 softtabstop=2 expandtab
setlocal spell

" Textwrap at 80 columns
call lib#changeTextWidth(80)

" Set folding for 3-backtick markdown divider block
setlocal foldmethod=marker foldmarker={{{,}}}
setlocal foldlevel=1

" For bulleted lists
setlocal autoindent
setlocal comments=fb:*
setlocal formatoptions=tcqj
setlocal formatlistpat=^\\s*[-*+]\\s\\+\\ze\\S

" This allows links to be displayed prettier
setlocal nowrap
setlocal conceallevel=2
setlocal concealcursor=nc

"Show how deep in folds each line is in the left columns
setlocal foldcolumn=2

" Invoke my plugin
call notes#init()

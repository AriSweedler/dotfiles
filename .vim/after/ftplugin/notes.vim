" Set folding for 3-backtick markdown divider block
call ChangeTextWidth(80)
set tabstop=2 shiftwidth=2 softtabstop=2 expandtab
set spell

" For folds
set foldmethod=marker foldmarker={{{,}}}
set foldlevel=1

" For comments
set autoindent
set comments=fb:*
set formatoptions=tcqj
set formatlistpat=^\\s*[-*+]\\s\\+\\ze\\S

" Invoke my plugin
call notes#init()

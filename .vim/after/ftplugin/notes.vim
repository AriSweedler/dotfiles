" Set folding for 3-backtick markdown divider block
call ChangeTextWidth(80)
set tabstop=2 shiftwidth=2 softtabstop=2 expandtab

" For folds
set foldmethod=marker foldmarker={{{,}}}
set foldlevel=1

" For comments
set autoindent
set formatoptions=tcqj
set formatlistpat=^\\s*[-*+]\\s\\+\\ze\\S

" For copy/pasting that BS
function! FixPastedFunction()
  %substitute/â/-/e
  %substitute/â/'/e
  %substitute/â/"/e
  %substitute/â/"/e
endfunction
command! FixMe keeppatterns call FixPastedFunction()

" Still notes'ing in md, but not for long (TODO)
command! -nargs=1 Foldo keeppatterns g/^{{{ <args>/normal zx
command! DoneBeGone keeppatterns g/[!*] DONE/d
call notes#init()

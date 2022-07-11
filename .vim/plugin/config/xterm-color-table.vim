" TODO optional arg to call the whatever (Xterm('V')) or something. Defaults
" V for VSPLIT
command! Xterm call VXterm()
command! XTerm call VXterm()
function! VXterm()
  if !exists('g:XtermColorTableDefaultOpen')
    packadd xterm-color-table
  endif
  VXtermColorTable
endfunction

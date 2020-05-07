""""""""""""""""""""""""" Vimscript file for syntaxer """"""""""""""""""""""""
"{{{ Debug
let s:debugging = 0
function! s:ToggleDebug()
  if s:debugging == 1
    autocmd! syntaxer *

    let s:debugging = 0
  else
    augroup syntaxer
      autocmd!

      autocmd CursorMoved * normal zS
    augroup END

    let s:debugging = 1
  endif
  echo "Debugging in now " . s:debugging
endfunction
command! ToggleSyntaxerDebug call s:ToggleDebug()
"}}}

"{{{ Refresh syntax
command! RefreshSyntax syntax clear <Bar> set filetype=notes
"}}}

echom expand("<sfile>") . " sourced"

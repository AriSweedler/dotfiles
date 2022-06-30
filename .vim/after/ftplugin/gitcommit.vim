nnoremap <buffer> <C-p> :set paste!<CR>

" Format bulleted lists properly
setlocal tabstop=2 autoindent
" inoremap <buffer> <silent> 8 <Esc>:call <SID>Bullet()<CR>A
function! s:Bullet()
  " This is a repeat invocation. Just remove 2 chars from the start to
  " de-indent.
  if getline('.')->match('^\s\+\*\s\+$') != -1
    normal 0xx$
    return
  endif

  " Don't make a bullet on the second line
  let [_, lnum, _, _, _] = getcurpos()
  if lnum == 1
    execute "normal j"
  endif

  " New bullet (on the same indent level as we were before
  if getline('.')->match('^\s\+\*') != -1
    execute "normal o*\<C-c>A\<Space>"
  else
    execute "normal o*\<C-c>V<A\<Space>"
  endif
endfunction

" wrap text and highlight columns
setlocal textwidth=72
setlocal colorcolumn=50,72

" Misc options
setlocal spell
setlocal expandtab
setlocal foldmethod=marker foldlevel=1

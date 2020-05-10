""""""""""""""""""""""""""""" vimscript development """""""""""""""""""""""""{{{
" Shortcuts to source/edit your vimrc/current file/ftplugin file {{{

" We need a function to lazily evaluate the filetype. If we hard-coded it with
" a mapping to ':tabe "$HOME/.vim/after/ftplugin/" . &filetype .  ".vim"<CR>', then
" we'd have to make a new mapping with every new buffer. That could be done
" with an autocommand, I suppose. But at this point, let's just use a function
" to delay evaluation of filetype until we invoke the function!

" Get a path using the filetype of the current file
function! Evaluate_path(path_start)
  return a:path_start . &filetype . ".vim"
endfunction

" source my {vimrc,current,ftplugin,syntax} file - useful for developing
nnoremap <silent> <Leader>sv :source $MYVIMRC<CR>
nnoremap <silent> <Leader>so :source %<CR>
nnoremap <silent> <Leader>sf :source <C-r>=Evaluate_path("$HOME/.vim/after/ftplugin/")<CR><CR>
nnoremap <silent> <Leader>ss :source <C-r>=Evaluate_path("$HOME/.vim/after/syntax/")<CR><CR>

" edit my {vimrc,ftplugin,syntax} file - useful for developing
nnoremap <silent> <Leader>ev :tabe $MYVIMRC<CR>
nnoremap <silent> <Leader>ef :tabe <C-r>=Evaluate_path("$HOME/.vim/after/ftplugin/")<CR><CR>
nnoremap <silent> <Leader>es :tabe <C-r>=Evaluate_path("$HOME/.vim/after/syntax/")<CR><CR>
nnoremap <silent> <Leader><Leader>es :tabe <C-r>=Evaluate_path("$VIMRUNTIME/syntax/")<CR><CR>
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""""""""""""" Syntax """""""""""""""""""""""""""""""""{{{
"{{{ Show syntax stack every time you move cursor (requires tpope's scripttease)
let s:debugging = 0
function! s:ToggleDebugSyntax()
  if s:debugging == 1
    autocmd! debugSyntax *

    let s:debugging = 0
  else
    augroup debugSyntax
      autocmd!

      autocmd CursorMoved * normal zS
    augroup END

    let s:debugging = 1
  endif
  echo "Debugging in now " . s:debugging
endfunction
command! ToggleSyntaxerDebug call s:ToggleDebugSyntax()
"}}}
"{{{ Refresh syntax
command! RefreshSyntax syntax clear <Bar> let &filetype=&filetype
"}}}
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}

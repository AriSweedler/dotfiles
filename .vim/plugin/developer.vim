""""""""" vimscript development """"""""
" Add shortcuts to source/edit your vimrc/current file/ftplugin file

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

" TODO add an alias in bash_aliases to start vim with nothing. ':help vimrc'
"
" From ":help vimrc":
" If Vim was started with "-u filename", the file "filename" is used.
" All following initializations until 4. are skipped. $MYVIMRC is not
" set.
" "vim -u NORC" can be used to skip these initializations without
" reading a file.  "vim -u NONE" also skips loading plugins.  |-u|

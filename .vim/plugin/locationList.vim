" TODO change to localtion list instead of quickfix (quickfix is too " global...)
" TODO make a separate plugin that does per-buffer toggling of location lists
function! QuickfixToggle()
  if b:quickfix_is_open
    echom "yes quickfix_is_open variable"
    return
  endif

  if (b:quickfix_is_open && &buftype == "quickfix")
    cclose
    let b:quickfix_is_open = 0
    execute b:quickfix_return_to_window . "wincmd w"
  else
    let b:quickfix_return_to_window = winnr()
    copen
    resize 15
    let b:quickfix_is_open = 1
  endif
endfunction

function! InitQuickfixOpenVariable()
    " A buffer local window for the quickfix list's state
    let b:quickfix_is_open = 0
endfunction

augroup quickfix
  autocmd!
  autocmd BufReadPost * call InitQuickfixOpenVariable()
  nnoremap <leader>qw :cnext<cr>
  nnoremap <leader>qW :cprevious<cr>
  nnoremap <leader>qq :call QuickfixToggle()<cr>
augroup END

echo "sourced"

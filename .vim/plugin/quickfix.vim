nnoremap <leader>qw :cnext<cr>
nnoremap <leader>qW :cprevious<cr>
nnoremap <leader>qq :call QuickfixToggle()<cr>

let g:quickfix_is_open = 0

function! QuickfixToggle()
  if (g:quickfix_is_open && &buftype == "quickfix")
    cclose
    let g:quickfix_is_open = 0
    execute g:quickfix_return_to_window . "wincmd w"
  else
    let g:quickfix_return_to_window = winnr()
    copen
    resize 15
    let g:quickfix_is_open = 1
  endif
endfunction

nnoremap <Leader>qw :cnext<CR>
nnoremap <Leader>qe :cprevious<CR>
nnoremap <Leader>q1 :call QuickfixToggle()<CR>
nnoremap <Leader>qq :call QuickfixToggle()<CR>
nnoremap <Leader>qg :call QuickfixToggle()<CR><CR>
nnoremap <Leader>qc :cclose<CR>

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

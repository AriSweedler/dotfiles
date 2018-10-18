let g:quickfix_open = 0

"Toggle the quickfix window open or closed
function! QuickFixToggle ()

  "If it's open, close it and mark it as closed.
  if g:quickfix_open
    cclose
    let g:quickfix_open = 0
  else
    copen
    let g:quickfix_open = 1
  endif
endfunction

"Use <Leader>c to toggle the window open or closed
nmap <Leader>c  :call QuickFixToggle()<CR>

" The beginning ofm y syntax writing plugin

augroup syntaxer
  " remove all syntaxer commands
  " To do this manually, just say `:autocmd! syntaxer *`
  autocmd!

  autocmd CursorMoved *.vim call MyFunction()
augroup END

let b:event_counter = 0
function! MyFunction()
  let l:event = printf("Event %d", b:event_counter)
  let b:event_counter = b:event_counter + 1


  let [_bufnum, line_num, column, _off, _curswant] = getcurpos()
  let l:syn = synID(line_num, column, 0)->synIDattr('name')
  if l:syn == ""
    let l:syn = "nothing"
  endif
  echom printf("[%s]: You are on syntax item '%s'", l:event, l:syn)
endfunction

echom expand('%') . " sourced"
finish

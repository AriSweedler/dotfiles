" The beginning of my syntax writing plugin

function! s:SyntaxUnderCursor()
  if !exists('b:event_counter')
    let b:event_counter = 0
  endif

  let l:event = printf("Event %d", b:event_counter)
  let b:event_counter = b:event_counter + 1

  let [_bufnum, line_num, column, _off, _curswant] = getcurpos()
  let l:syn = synID(line_num, column, 0)->synIDattr('name')
  if l:syn == ""
    let l:syn = "nothing"
  endif
  echom printf("[%s]: You are on syntax item '%s'", l:event, l:syn)
endfunction

function! s:SyntaxStack()
  let l:mylist = [{"text": "TOP LEVEL"}, {"text": "_________"}]
  for id in synstack(line("."), col("."))
    let l:syn = synIDattr(id, "name")
    call add(l:mylist, {"text": l:syn})
  endfor
  call setqflist(l:mylist)
endfunction

let s:debugging = 0
function! s:ToggleDebug()
  if s:debugging == 1
    autocmd! syntaxer *

    let s:debugging = 0
  else
    augroup syntaxer
      autocmd!

      autocmd CursorMoved *.vim call s:SyntaxUnderCursor()
      autocmd CursorMoved *.notes call s:SyntaxUnderCursor() | call s:SyntaxStack()
    augroup END

    let s:debugging = 1
  endif
  echo "Debugging in now " . s:debugging
endfunction

command! ToggleSyntaxerDebug call s:ToggleDebug()

echom expand("<sfile>") . " sourced"
finish

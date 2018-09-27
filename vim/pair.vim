" All the pairs that'll act fancy
let s:pair = {
\ '"': '"',
\ '{': '}',
\ '(': ')',
\ '[': ']',
\ '<': '>',
\}

" make keymappings
for [opener, closer] in items(s:pair)
  execute printf("inoremap %s <C-r>=InsertPair('%s', '%s')<CR>", opener,
\      opener, closer)
  execute printf("inoremap %s <C-r>=StepOver('%s')<CR>", closer, closer)
endfor

" Typing the opener will also insert the closer
function! InsertPair(open, close)
  return a:open . a:close . "\<Left>"
endfunction

" typing the closer over itself will simply move your cursor to the right
function! StepOver(closer)
  if CurChar() == a:closer
    return "\<Right>"
  endif
  return a:closer
endfunction

" Have delete undo what the IDE-like enhancements do...
inoremap <BS> <C-r>=DeletePair()<CR>
function! DeletePair()
  " find cur and prev chars
  let prev = CurChar(-1)
  let cur = CurChar(0)

  " if applicable, delete both
  for [opener, closer] in items(s:pair)
    if l:prev == opener && l:cur == closer
      return "\<Right>\<BS>\<BS>"
    endif
  endfor

  return "\<BS>"
endfunction


let g:notes#banglist#pattern_start = '\* \<\zs'
let g:notes#banglist#pattern_end = '\ze\>.*!'

let g:notes#banglist#src = 'DO'
let g:notes#banglist#dst = 'DONE'

" Finds the next line containing src and changes it to dst. If 'slide' is set to
" true, first changes this line from dst to src.
function! notes#banglist#subslide(slide, src, dst)
  " Convenience variables
  let l:src_pat = notes#banglist#item(a:src)
  let l:dst_pat = notes#banglist#item(a:dst)

  " Move to the start of the line before executing forward search, so
  " invocations work linewise isntead of characterwise
  normal ^

  if a:slide
    " Undo the substitution on this line and go to the next pattern
    execute "substitute/" . l:dst_pat . "/" . a:src . "/e"
    normal $
  endif

  call search(l:src_pat)
  execute "substitute/" . l:src_pat . "/" . a:dst . "/e"
  call search(l:dst_pat)
endfunction

function! notes#banglist#item(name)
  return g:notes#banglist#pattern_start . a:name . g:notes#banglist#pattern_end
endfunction

" Wrapper function to call banglist. Tracks cursor movement & opens folds
" With 0 arguments, repeat last sequence (or start a DO/DONE)
" With 1 argument, just find.
" With 2 arguemnts, sub src for dst. (if unmoved, slide instead of sub)
function! notes#banglist#controller(...)
  let l:unmoved = notes#CursorUnmoved("notes#banglist")

  if a:0 == 0
    if ! l:unmoved
      " The invocation is a new sequence of DO/DONE
      let g:notes#banglist#src = 'DO'
      let g:notes#banglist#dst = 'DONE'
    endif
  elseif a:0 == 1
    " subslide with identical arguments acts like search. Sloppy but w/e lol
    let g:notes#banglist#dst = a:1
  else
    let g:notes#banglist#src = a:1
    let g:notes#banglist#dst = a:2
  endif

  " If cursor is unmoved between invocations, slide instead of sub
  let l:should_slide = l:unmoved
  call notes#banglist#subslide(l:should_slide, g:notes#banglist#src, g:notes#banglist#dst)

  " Open folds if needed
  silent! normal! zO

  " Invoke CursorUnmoved to set the "unmoved cursor position"
  call notes#CursorUnmoved("notes#banglist")
endfunction



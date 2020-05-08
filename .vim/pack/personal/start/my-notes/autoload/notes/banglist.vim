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
  let l:unmoved = notes#banglist#CursorUnmoved('controller')

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
  call notes#banglist#CursorUnmoved('controller')
endfunction

" Toggle between 27 and 238. Half optimized for literally no reason haha !
let g:notes#banglist#bb_color = 238
function! notes#banglist#toggle_backburner_highlight()
  let g:notes#banglist#bb_color = 27 + (238-27)*(g:notes#banglist#bb_color == 27)
  execute "highlight notesBackburner term=standout ctermfg=" . g:notes#banglist#bb_color
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" TODO move to utility folder
" Originally this was built to be very general, but then I only use it here so I
" just transplanted it. It's actually a utility function
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Helper function to check if the cursor has moved since the last invocation
" of this function.
let g:notes#banglist#prev_cur_pos = {}
function! notes#banglist#CursorUnmoved(tag)
  let prev = exists("g:notes#banglist#prev_cur_pos[a:tag]") ? g:notes#banglist#prev_cur_pos[a:tag] : [0]
  let answer = (l:prev == getpos('.'))

  " Update tag's prev_cur_pos and return the answer
  let g:notes#banglist#prev_cur_pos[a:tag] = getpos('.')
  return answer
endfunction

""""""""""""""""""""""""""""" banglist autoload """""""""""""""""""""""""""" {{{
"""""""""""""""""""""""""""""" banglist items """""""""""""""""""""""""""""" {{{
let g:notes#banglist#pattern_start = '\* \<\zs'
let g:notes#banglist#pattern_end = '\ze\>.*!'
" Returns a regex to select for banglist items. Of the form
" "\* \<\zsITEM\ze\>.*!" instead of just "ITEM".
function! notes#banglist#item(name)
  return g:notes#banglist#pattern_start . a:name . g:notes#banglist#pattern_end
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""""""" subslide """"""""""""""""""""""""""""""""" {{{
let g:notes#banglist#src = 'DO'
let g:notes#banglist#dst = 'DONE'
" Finds the next line containing src and changes it to dst. If 'slide' is set to
" true, first changes this line from dst to src.
"
" TODO WHY DOES INVOKING ON THE BEGINNING OF PATTERN FAIL?
function! notes#banglist#subslide(slide, src, dst)
  " Convenience variables
  let l:src_pat = notes#banglist#item(a:src)
  let l:dst_pat = notes#banglist#item(a:dst)

  " Move to the start of the line before executing forward search, so
  " invocations work linewise isntead of characterwise
  normal 0

  if a:slide
    " Undo the substitution on this line and go to the next pattern
    execute "substitute/" . l:dst_pat . "/" . a:src . "/e"
    normal $
  endif

  call search(l:src_pat)
  normal zx
  execute "substitute/" . l:src_pat . "/" . a:dst . "/e"
  call search(l:dst_pat)
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""""" banglist controller """"""""""""""""""""""""""" {{{
" Wrapper function to call banglist. Tracks cursor movement & opens folds
" With 0 arguments, repeat last sequence (or start a DO/DONE)
" With 1 argument, just find.
" With 2 arguments, sub src for dst. (if unmoved, slide instead of sub)
function! notes#banglist#controller(...)
  let l:unmoved = lib#cursorUnmoved('banglist')

  if a:0 == 0
    if ! l:unmoved
      " No arguments, but we have moved. Interpret this as a new sequence of
      " changing DO ==> DONE
      let g:notes#banglist#src = 'DO'
      let g:notes#banglist#dst = 'DONE'
    endif
    " No arguments, and we have not moved. Use the same src/dst as last time.
  elseif a:0 == 1
    " subslide with identical arguments acts like search. Sloppy but w/e lol
    let g:notes#banglist#src = a:1
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
  call lib#cursorUnmoved('banglist')
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""" backburner highlight """"""""""""""""""""""""""" {{{
" Toggle between 27 and 238. Half optimized for literally no reason haha !
let g:notes#banglist#bb_color = 238
function! notes#banglist#toggle_backburner_highlight()
  let g:notes#banglist#bb_color = 27 + (238-27)*(g:notes#banglist#bb_color == 27)
  execute "highlight notesBackburner term=standout ctermfg=" . g:notes#banglist#bb_color
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""""" DONE highlight """""""""""""""""""""""""""""" {{{
"" Toggle between 23 and 238. Half optimized for literally no reason haha !
"let g:notes#banglist#dd_color = 23
"function! notes#banglist#toggle_done_highlight()
"  let g:notes#banglist#dd_color = 23 + (238-23)*(g:notes#banglist#dd_color == 23)
"  execute "highlight notesDONE term=standout ctermfg=" . g:notes#banglist#dd_color
"endfunction
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""""""""""" global """""""""""""""""""""""""""""""""" {{{
" Acts just like :global, but only checks for banglist items. This is stricter
" and more semantically useful sometimes
function! notes#banglist#global(src, command)
  let l:command = printf("global/%s/%s", notes#banglist#item(a:src), a:command)
  execute l:command
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}

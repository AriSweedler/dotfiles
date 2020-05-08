let g:notes#banglist#pattern_start = '\* \<\zs'
let g:notes#banglist#pattern_end = '\ze\>.*!'

let g:notes#banglist#src = 'DO'
let g:notes#banglist#dst = 'DONE'

" Finds the next line containing src and changes it to dst. If 'slide' is set to
" true, first changes this line from dst to src.
function! notes#banglist#main(slide, src, dst)
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

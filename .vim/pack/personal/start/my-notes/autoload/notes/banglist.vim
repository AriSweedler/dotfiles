let g:notes#banglist#pattern_start = '\* \<\zs'
let g:notes#banglist#pattern_end = '\ze\>.*!'
let g:notes#banglist#ver = 2

function! notes#banglist#main(dict)
  " dict has a MODE (find, sub, slide)
  " dict has a SRC
  " dict has a DST
  "
  " sliding a DONE-->DO ==> mode=slide src=DONE dst=DO
  " finding a DO        ==> mode=find  src=DO
  " subbing a DO-->DONE ==> mode=sub   src=DO   dst=DONE

  let l:pat = notes#banglist#item(a:dict['src'])

  if a:dict['mode'] == "find"
    " Find the right line
    call search(l:pat)
    return
  elseif a:dict['mode'] == "sub"
    " Find the right line and make the substitution
    call search(l:pat)
    execute "substitute/" . l:pat . "/" . a:dict['dst'] . "/e"
    let l:pat = notes#banglist#item(a:dict['dst'])
  elseif a:dict['mode'] == "slide"
    " TODO this doesn't work :c
    " Undo the substitution and go to the pattern (instead of the beginning of the line)
    execute "substitute/" . l:pat . "/" . a:dict['dst'] . "/e"

    " Go to the next pattern and redo the substitution
    let l:pat = notes#banglist#item(a:dict['dst'])
    call search(l:pat)
    call search(l:pat)
    execute "substitute/" . l:pat . "/" . a:dict['src'] . "/e"
  else
    echo "unknown mode"
    return
  endif
endfunction

function! notes#banglist#item(name)
  return g:notes#banglist#pattern_start . a:name . g:notes#banglist#pattern_end
endfunction

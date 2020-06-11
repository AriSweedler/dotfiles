" Helper function to check if the cursor has moved since the last invocation
" of this function.
let g:lib#prev_cur_pos = {}
function! lib#cursorUnmoved(tag)
  let prev = exists("g:lib#prev_cur_pos[a:tag]") ? g:lib#prev_cur_pos[a:tag] : [0]
  let answer = (l:prev == getpos('.'))

  " Update tag's prev_cur_pos and return the answer
  let g:lib#prev_cur_pos[a:tag] = getpos('.')
  return answer
endfunction

" Use colorcolumn to display the textwidth
function! lib#changeTextWidth(...)
  " If we have a v:count, then set the textwidth.
  if a:0 == 1
    let l:width = a:1
    let &textwidth = (l:width)
  endif

  " match the colorcolumn to the textwidth
  let &colorcolumn = (&textwidth)
endfunction

" Toggle syntax on or off
function! lib#toggleSyntax()
  let &syntax=(&syntax == "OFF") ? &filetype : "OFF"
endfunction

" remove trailing whitespace - https://vi.stackexchange.com/questions/454/
function! lib#removeTrailingWhitespace(range)
  let save_pos = getpos(".")
  let trailing = '\s\+$'
  execute 'keeppatterns ' . a:range . 'substitute/' . l:trailing . '//e'
  call setpos('.', save_pos)
endfunction

let g:lib#showLeftColumns = 1
function! lib#toggleLeftColumns()
  if g:lib#showLeftColumns
    " Turn all the gutter info OFF
    let g:lib#showLeftColumns = 0
    GitGutterDisable
    set nonumber
    set signcolumn=no
    set foldcolumn=0
  else
    " Turn all the gutter info ON
    let g:lib#showLeftColumns = 1
    GitGutterEnable
    set number
    set signcolumn=yes
    set foldcolumn=2
  endif
endfunction

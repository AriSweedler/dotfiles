"""""""""""""""""""""""""""""""" Include guard """""""""""""""""""""""""""""""
if exists("g:loaded_range")
  finish
endif
let g:loaded_range = 1
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

"""""""""""""""""""""""""""""""" Function body """""""""""""""""""""""""""""""
function MakeRange(start, end, increment)
  let l:numbers = []
  let l:val = a:start
  while l:val <= a:end
    call add(l:numbers, l:val)
    let val = l:val + a:increment
  endwhile
  let ans = '"' . join(l:numbers, '", "') . '"'
  put =l:ans
endfunction
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" I don't wanna type ALL of this. Just the numbers.
nnoremap <Leader>R :call MakeRange(

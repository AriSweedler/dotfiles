func Nr2Bin(nr)
  let n = a:nr
  let r = ""
  while n
    let r = '01'[n % 2] . r
    let n = n / 2
  endwhile
  return r
endfunc

nnoremap <Leader>Bin yiw:put =Nr2Bin(<C-r>")<CR>

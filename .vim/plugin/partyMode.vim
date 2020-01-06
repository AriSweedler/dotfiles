function! PartyMode(revolutions)
  let i = 0
  while i < a:revolutions
    set rightleft!
    redraw
    sleep 100m
    let i = i + 0.5
  endwhile
endfunction
nnoremap <Leader><Leader>p :<C-u>call PartyMode(v:count)<CR>

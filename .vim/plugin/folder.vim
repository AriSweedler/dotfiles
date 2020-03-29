" Cute little function to help you create a titled fold
function! s:NewFold()
  if &foldmethod != "marker"
    echom "Foldmethod not set to marker"
    return
  endif

  if !exists("&foldmarker")
    echom "Foldmarker not set"
    return
  endif

  let my_foldmarkers = split(&foldmarker, ",")
  put =l:my_foldmarkers[0]
  put =l:my_foldmarkers[1]
endfunction
nnoremap <Leader>f :call <SID>NewFold()<CR>zxkA<Space>

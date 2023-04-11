" Perhaps this 's:make_folds' function belongs in a library
setlocal foldmethod=manual
function! s:make_folds()
  setlocal foldlevel=10
  normal zE
  let foldables = [
\   "service .* {$",
\   "message .* {$",
\   "enum .* {$",
\   "rpc .* {$",
\ ]
  for pat in foldables
    execute "silent global/".pat."/normal $zfaBzO"
  endfor

  setlocal foldlevel=0
endfunction
call s:make_folds()

setlocal autoindent tabstop=2 expandtab

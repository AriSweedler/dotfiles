function! SetTabs(num)
  let myCommand = printf("set tabstop=%d softtabstop=%d shiftwidth=%d",
\   a:num, a:num, a:num)
  execute l:myCommand
  set expandtab
  %norm >><<
  echo "Changed tabs to be worth " . a:num
endfunction

noremap <Leader>t :<C-u>call SetTabs(v:count1)<CR>


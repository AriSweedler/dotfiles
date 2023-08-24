let g:codeium_enabled = v:false
let g:codeium_disable_bindings = 1 " I will make my own

function! CodeiumEnableFunction(buf)
  " Do work
  packadd codeium.vim
  execute printf('Codeium %s', a:buf)
  redraw!

  " No more work to do for the Buffer case
  if a:buf == "EnableBuffer"
    return
  endif

  " Set mappings
  imap <script><silent><nowait><expr> <Tab> codeium#Accept()
  imap <M-n>   <Cmd>call codeium#CycleCompletions(1)<CR>
  imap <M-p>   <Cmd>call codeium#CycleCompletions(0)<CR>
  imap <C-c>   <Cmd>call codeium#Clear()<CR>
endfunction

function! CodeiumDisableFunction(buf)
  " Exit early if we are alreay disabled
  if g:codeium_enabled == v:false
    return
  endif

  " Do work
  execute printf('Codeium %s', a:buf)
  redraw!

  " No more work to do for the Buffer case
  if a:buf == "DisableBuffer"
    return
  endif

  " Unset mappings when we disable for real
  iunmap <Tab>
  iunmap <M-n>
  iunmap <M-p>
  iunmap <C-c>
endfunction

" EnableBuffer and disable
nnoremap <expr> <Leader><Leader>ce CodeiumEnableFunction("Enable")
nnoremap <expr> <Leader><Leader>cd CodeiumDisableFunction("Disable")
nnoremap <expr> <Leader><Leader>bcd CodeiumDisableFunction("DisableBuffer")
nnoremap <expr> <Leader><Leader>bce CodeiumEnableFunction("EnableBuffer")

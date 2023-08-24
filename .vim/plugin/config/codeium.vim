let g:codeium_disable_bindings = 1

imap <script><silent><nowait><expr> <C-h> codeium#Accept()
imap <C-n>   <Cmd>call codeium#CycleCompletions(1)<CR>
imap <C-p>   <Cmd>call codeium#CycleCompletions(-1)<CR>
imap <C-x>   <Cmd>call codeium#Clear()<CR>

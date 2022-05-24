" Search for UUIDs
nnoremap <buffer> <Leader>u /\x\{8}-\x\{4}-\x\{4}-\x\{4}-\x\{12}<CR>

" Reload the buffer (when the underlying file has been updated)
nnoremap <buffer> <silent> ! :edit! %<CR>

" <Leader>f to set the command we wanna fetch with
" <Leader>F to execute the fetch and reload the current buffer
let b:fetch_log_cmd = ""
nnoremap <buffer> <Leader>r :let b:fetch_log_cmd = "!FILLMEOUT"
nnoremap <buffer> <Leader>R :execute b:fetch_log_cmd<CR>:edit! %<CR>

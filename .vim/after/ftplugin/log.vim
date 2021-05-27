" Filter visually selected lines through python's json pretty-printer
vnoremap <buffer> J :!python3 -m json.tool<CR>

" Search for UUIDs
nnoremap <buffer> <Leader>u /\x\{8}-\x\{4}-\x\{4}-\x\{4}-\x\{12}<CR>

" <Leader>R to reload the file (We might need to fetch it)
" <Leader>r to set the command we wanna fetch with
let g:log_reload_file = "!echo 'how do you want to reload me?'"
nnoremap <buffer> <Leader>r :let g:log_reload_file = "!
nnoremap <buffer> <Leader>R :execute g:log_reload_file<CR>:edit! %<CR>

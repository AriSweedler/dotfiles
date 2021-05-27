" Filter visually selected lines through python's json pretty-printer
vnoremap J :!python3 -m json.tool<CR>

" Search for UUIDs
nnoremap <Leader>u /\x\{8}-\x\{4}-\x\{4}-\x\{4}-\x\{12}<CR>

" <Leader>R to reload the file (We might need to fetch it)
" <Leader>r to set the command we wanna fetch with
let g:log_reload_file = "!scp v-sol10u8:/opt/illumio_ven_data/log/platform.log ~/Desktop/nexus/log/platform.log"
nnoremap <Leader>r :let g:log_reload_file = "!
nnoremap <Leader>R :execute g:log_reload_file<CR>:edit! %<CR>

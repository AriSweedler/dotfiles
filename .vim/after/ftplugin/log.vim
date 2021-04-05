" Filter visually selected lines through python's json pretty-printer
vnoremap J :!python3 -m json.tool<CR>

" Search for UUIDs
nnoremap <Leader>u /\x\{8}-\x\{4}-\x\{4}-\x\{4}-\x\{12}<CR>

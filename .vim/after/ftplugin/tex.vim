set tabstop=2 shiftwidth=2 expandtab

" Make a command to compile
noremap  <silent> <C-h> <ESC>:call RemoveTrailingWhitespace('.')<CR>:w<CR>:!pdflatex %<CR>
noremap! <silent> <C-h> <ESC>:call RemoveTrailingWhitespace('.')<CR>:w<CR>:!pdflatex %<CR>

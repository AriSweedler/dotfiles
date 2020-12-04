set tabstop=2 expandtab
set foldmethod=marker foldmarker=%-->,%<--

" Make a command to compile
if mapcheck("\<C-g>") != ""
  unmap <C-g>
endif
noremap <silent> <C-h> <ESC>:call lib#removeTrailingWhitespace('.')<CR>:w<CR>:!pdflatex %<CR>
noremap <silent> <C-j> <ESC>:!open %:r.pdf<CR>

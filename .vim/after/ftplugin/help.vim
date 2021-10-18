" These two settings make for a nice reader view. Maybe I should make them
" toggleable as a library function.
setlocal cursorline
setlocal scrolloff=999

" I have bad muscle memory. Disable my <C-f> mapping
noremap <buffer> <C-f> <Nop>

" Move to the next 'help' entry. Assume they are separated by two newlines.
" Set a mark in the jumplist then go.
nnoremap <buffer> } m':call search('^$\n^$')<CR>jj
nnoremap <buffer> { 2km':call search('^$\n^$', 'b')<CR>jj

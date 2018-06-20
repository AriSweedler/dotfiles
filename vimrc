syntax on
colorscheme desert
set number
set display=lastline

set hlsearch
set incsearch
" Remap control+underscore to clear the the register '/'.
" This is the register that controls highlighting
noremap <silent> <c-_> :let @/ = ""<CR> 

" The default is a measly 40!
set history=1000

" Nicer <C-d>/<Tab>'ing
set wildmenu
set wildmode=full


" Tab stuff. For more info, look to 'http://vimcasts.org/transcripts/2/en/'
filetype on
"autocmd FileType ?akefile setlocal tabstop=8 softtabstop=0 shiftwidth=8 noexpandtab
"autocmd FileType *.c setlocal sts=2 sw=2 ts=2 et

" easily switch between buffers (tabs)
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>

" Putting on these anti-training wheels until I break the habit
noremap <Up> <Nop>
noremap <Down> <Nop>
noremap <Left> <Nop>
noremap <Right> <Nop>

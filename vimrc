syntax on
colorscheme desert
set number
set display=lastline

set hlsearch
set incsearch
" Remap control+underscore to clear the the register '/'.
" This is the register that controls highlighting
noremap <silent> <C-_> :let @/ = ""<CR>

" The default is a measly 40!
set history=1000

" Nicer <C-d>/<Tab>'ing
set wildmenu
set wildmode=full

" Tab stuff. For more info, look to 'http://vimcasts.org/transcripts/2/en/'
" expandtab - (when enabled) causes spaces to be used in place of tab characters
" softtabstop - (when enabled) amount of whitespace to be inserted by hitting <tab>
" shiftwidth - amount of whitespace to insert or remove using the indentation commands
" tabstop - specifies the width of a tab character
filetype on
autocmd FileType c** setlocal tabstop=4 shiftwidth=4 softtabstop=4 expandtab 
	\ foldmethod=syntax cindent
autocmd FileType make* setlocal tabstop=8 shiftwidth=8 noexpandtab

" easily switch between buffers (tabs)
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>

" fold commands
noremap <C-m> zfiB
noremap zz za

" Nicer file traversing
noremap <up> <C-y>k
noremap <C-p> <C-y>k
noremap <down> <C-e>j
noremap <C-n> <C-e>j

" no need to use these
noremap <Left> <Nop>
noremap <Right> <Nop>

" ctags is so helpful! And easy, too. 
" https://medium.freecodecamp.org/make-your-vim-smarter-using-ctrlp-and-ctags-846fc12178a4
set tags+=tags;

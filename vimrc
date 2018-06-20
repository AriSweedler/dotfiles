colorscheme elflord
set number
set display=lastline

" turn highlighting on. Remove highlights with <C-_>
set hlsearch
noremap <silent> <c-_> :let @/ = ""<CR> 

" The default is a measly 40!
set history=1000

" Nicer <C-d>/<Tab>'ing
set wildmenu
set wildmode=full

" expandtab, tabstop, softtabstop, shiftwidth (look at http://vimcasts.org/transcripts/2/en/)
set sts=4 sw=4 tabstop=4 expandtab

" easily switch between buffers (tabs)
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>

" Putting on these anti-training wheels until I break the habit
noremap <Up> <Nop>
noremap <Down> <Nop>
noremap <Left> <Nop>
noremap <Right> <Nop>

""""""""""""""""""""""""""""""""""" Tabs """"""""""""""""""""""""""""""""""" {{{
" Find tab navigation easier with 'gr/gt' than 'gT/gt'
nnoremap gr gT

" tabmove more easily
nnoremap ]t :tabm+<CR>
nnoremap [t :tabm-<CR>

" <C-w>T moves a window to a new tab, but I like '!' better. Like tmux
nnoremap <C-w>! <C-w>T
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""""""" buffer cleanup """""""""""""""""""""""""""""" {{{
" remove buffer from memory
nnoremap <Leader>bc :bnext <Bar> bdelete #<CR>

" Remove buffer from memory AND close the window
nnoremap <Leader>BC :.bdelete<CR>
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""" Switch between files more easily """""""""""""""""""" {{{
nnoremap [b :bprevious<CR>
nnoremap ]b :bnext<CR>

" TODO fuzzy find
nnoremap <C-b> :ls<CR>:buffer<Space>
" TODO fuzzy find
nnoremap <Leader>T :tabedit **/*

" Tabedit a file in the same directory as the current file
nnoremap <Leader>H :tabedit <C-r>=expand("%:h")<CR>/
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""""" Tabs and tags """""""""""""""""""""""""""""" {{{
" Re-run ctags
nnoremap <Leader><C-]> :!ctags -R .<CR>

" Open a tag in a new tab. Useful for tracing execution across a stack.
nnoremap g<C-]> :tab tag <C-r>=expand("<cword>")<CR><CR>

" Tselect tab in new tag
nnoremap g[] :tab tselect <C-r>=expand("<cword>")<CR><CR>
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}

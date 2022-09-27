" One keystroke to strip trailing whitespace on the current line and write in
" (almost) any mode
noremap  <C-f> <ESC>:call lib#remove_trailing_whitespace('.')<CR>:w<CR>
noremap! <C-f> <ESC>:call lib#remove_trailing_whitespace('.')<CR>:w<CR>
" Also... exit insert mode without having to move fingers.
inoremap jk <ESC>:call lib#remove_trailing_whitespace('.')<CR>

" <C-f> <C-g> will write and exit. Kinda emacs-y lol
nnoremap <C-g> :q<CR>

" When do I ever wanna hit 2 keys to execute one thought. Overwriting these
" isn't an issue as if I wanna operate on a range I can just use visual mode.
nnoremap Y yy
nnoremap D dd
nnoremap G Gzz
nnoremap < <<
nnoremap > >>
nnoremap Q "_

" if &wrap | move to start | else don't | endif
nnoremap zz ^zz
nnoremap zZ zz$

" Highlight this (virtual) column. Ability to jump up and down (past whitespace)
" gK because it's like 'k', which movies up, but different
nnoremap gK /\%<C-R>=virtcol(".")<CR>v\S<CR>N

" Fold commands are prefixed with 'z'. But movement commands are prefixed with
" '['. I think that either should work. But I prefer saying 'move fold' in my
" head rather than 'fold move'
nnoremap ]z zj
nnoremap [z zk

" Always use '\m' to 'Make'
nnoremap <Leader>m :lmake<CR>

" Write with sudo priviliges
cabbrev w!! w !sudo tee % > /dev/null

" No need to drop 'shift' when taking the head of the current path
cabbrev %:H %:h
cabbrev VH vsp %:h/
cabbrev vh vsp %:h/

" Turn 'diff' on for the 2 open windows in this tab.
" Turn off in all windows with 'diffoff!'
" TODO make 'DiffThis!' toggle this
command! DiffThis diffthis | wincmd w | diffthis | wincmd w

" Open up a scratch buffer named <args>
command! -nargs=1 Scratch :tabe <args> | setlocal buftype=nofile

" highlight search (highlight matches)
set hlsearch

" incremental search (highlight as we type the search query)
set incsearch

" Clear highlighting for search terms
noremap <silent> <C-_> :nohlsearch<CR>
inoremap <silent> <C-_> <C-o>:nohlsearch<CR>

" Improvements to '*' - work in visual mode & don't go to the next instance
" This one is sweet: use star in visual mode to search for the selected text
" yank into register 0 --> forward search for the contents of register 0
" (Very nomagic, escape contents of 0 register before pasting).
vnoremap <silent> * "0y:let@/='<C-r>=escape(@0, '/\')<CR>\V'<CR>
vnoremap <silent> g* "0y:lgrep! '<C-r>0'<CR>
nnoremap * *N

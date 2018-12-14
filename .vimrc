"TODO I need to also include my ~/.vim folder for these..

""""""""""""""""""""""""""""""""""" settings """"""""""""""""""""""""""""""""""
filetype on           "allow for autocmds to be run based on filetype
colorscheme desert    "pretty colors
set display=lastline  "as much as possible of the last line will be displayed
set gdefault          "turn global flag on by default for :substitute
set history=1000      "the default is only 40.
set nocompatible      "don't do weird stuff for backwards compatibility with vim
set number            "turn on line numbers
set showcmd           "multi-keystroke commands will be shown in bottom right.
set showmode          "show vim mode in bottom left
set noerrorbells      "disable error bells
set belloff=all       "disable bell for non-errors, too
set title             "show the filename in the title bar
set ruler             "display the cursor positiont

"allow backspacing over more things
set backspace=indent,eol,start

" Nicer <Tab>'ing in command mode
set wildmenu
set wildmode=full

" ctags is so helpful! And easy, too.
set tags+=tags;

" Toggle 'list' to show whitespace characters
set listchars=tab:X-,space:.,eol:$,
if (toupper(substitute(system('uname'), '\n', '', '')) =~# 'DARWIN')
  set listchars=tab:▶\ ,trail:~,space:·,eol:¬
endif

"""""""""""""""""""""""""""""""""" popup menu """"""""""""""""""""""""""""""""""
" show a popup menu for completion even if there's only 1 option
" Only insert the longest common text for a list of matches
set completeopt=menuone,longest
" max popup menu height is 8
set pumheight=8

"""""""""""""""""""""""""""""""""" whitespace """"""""""""""""""""""""""""""""""
" remove trailing whitespace upon saving or upon hitting <Leader>w
function! RemoveTrailingWhitespace()
  %substitute/\s\+$//e
endfunction
nnoremap <silent> <Leader>w :call RemoveTrailingWhitespace()<CR>

"""""""""""""""""""""""""""""""" pretty colors """"""""""""""""""""""""""""""""
" Look at colors: http://vim.wikia.com/wiki/Xterm256_color_names_for_console_Vim

"allow for syntax highlighting and indenting
syntax on

"highlight search
set hlsearch

"incremental search - show where hitting enter WOULD place you
set incsearch

"briefly show the matching bracket {[( when typing )]}
set showmatch matchtime=1

" highlight trailing whitespace
highlight trailing_whitespace ctermbg=red
match trailing_whitespace /\s\+$/

" highlight columns - highlight the 80th column
let &colorcolumn="80"
highlight ColorColumn ctermbg=233

"""""""""""""""""""""""""""""""" abbreviations """"""""""""""""""""""""""""""""
" easy hashbangs
iabbrev #!b #!/usr/bin/env bash
iabbrev #!p #!/usr/bin/env python
iabbrev #!s #!/usr/bin/env sh

"""""""""""""""""""""""""""""""""""" remap """"""""""""""""""""""""""""""""""""
"""""""""""""""" macros """"""""""""""""
" easy folds around braces
noremap <Leader>z %zfaB

" clear highlighting (clear the buffer, or just stop highlighting)
noremap <silent> <Leader>/ :let @/ = ""<CR>
noremap <silent> <C-_> :nohlsearch<CR>

" Save a file as root (\W)
nnoremap <Leader>WR :w !sudo tee % > /dev/null<CR>

" replace current word with most recently yanked text, preserving buffer
nnoremap <Leader>r viwpyiw

" indent/highlight most recently pasted code
nnoremap <Leader>= `[=`]
nnoremap <Leader>v `[v`]

" edit ~/.vimrc
nnoremap <Leader>ev :tabe $MYVIMRC<CR>

" use star in visual mode to search for the selected text
" yank into register s --> forward search for the contents of register s
" (Very nomagic, escape contents of s register before pasting)
vnoremap * "sy/\V<C-r>=escape(@s, '/\')<CR><CR>N
nnoremap * *N

" source my vimrc/current file - useful for testing
nnoremap <Leader>sv :source ~/.vimrc<CR>
nnoremap <Leader>so :source %<CR>

" go to the next/prev item in the quickfix list
nnoremap <Leader>q :cnext<CR>
nnoremap <Leader>Q :cprev<CR>

""""""""""""" buffers/tabs """""""""""""
" Remove buffer from memory without closing window
nnoremap <Leader>bd :bnext\|bdelete #<CR>

" "relative" edit. Edit a file without having to cd by using `% (filename) :p (full path) :h (dirname)`
map <leader>ew :edit <C-R>=expand("%:p:h") . "/" <CR>

" easily switch between buffers and tabs
nnoremap [b :bprevious<CR>
nnoremap ]b :bnext<CR>
nnoremap gr gT

""""""""""""""" movement """""""""""""""
nnoremap <Up> <C-y>k
nnoremap <Down> <C-e>j

"""""""""""""""" other """"""""""""""""
" Config for netrw: https://shapeshed.com/vim-netrw/
" Remove the banner
let g:netrw_banner = 0
" open files in a new tab
let g:netrw_browse_split = 3

" exit insert mode with 'jj<Space>'
inoremap jj <ESC>

" sessions
nmap <Leader>ss :wa<CR>:mksession! ~/.vim/sessions/
nmap <Leader>sess :wa<CR>:so ~/.vim/sessions/

" enable omnicompletion
set omnifunc=syntaxcomplete#Complete


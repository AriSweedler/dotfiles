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
set listchars=tab:▸\ ,space:·,eol:¬,

"""""""""""""""""""""""""""""""""" popup menu """"""""""""""""""""""""""""""""""
" show a popup menu for completion even if there's only 1 option
" Only insert the longest common text for a list of matches
set completeopt=menuone,longest
" max popup menu height is 8
set pumheight=8

"""""""""""""""""""""""""""""""""" whitespace """"""""""""""""""""""""""""""""""
" Tab stuff. For more info, look to
" https://medium.com/@arisweedler/tab-settings-in-vim-1ea0863c5990
autocmd FileType c**,python,java setlocal tabstop=4 shiftwidth=4 softtabstop=4 expandtab
autocmd Filetype c**,java setlocal cindent foldmethod=syntax textwidth=80
autocmd FileType make* setlocal tabstop=8 softtabstop=8 shiftwidth=8 noexpandtab
autocmd FileType vim,asm,javascript,sh setlocal tabstop=2 softtabstop=2 shiftwidth=2 expandtab

" remove trailing whitespace upon saving or upon hitting <Leader>w
function! RemoveTrailingWhitespace()
  %substitute/\s\+$//e
endfunction
nnoremap <silent> <Leader>w :call RemoveTrailingWhitespace()<CR>

"""""""""""""""""""""""""""""""" pretty colors """"""""""""""""""""""""""""""""
" Look at colors: http://vim.wikia.com/wiki/Xterm256_color_names_for_console_Vim

"""""""""""" color settings """"""""""""
"allow for syntax highlighting and indenting
syntax on

"highlight search
set hlsearch

"incremental search - show where hitting enter WOULD place you
set incsearch

"briefly show the matching bracket {[( when typing )]}
set showmatch matchtime=1

"""""""""""" color commands """"""""""""
" highlight trailing whitespace
highlight trailing_whitespace ctermbg=red
match trailing_whitespace /\s\+$/

" highlight the tilde when it's used as a path name in shell scripts
highlight bad_tilde ctermbg=red
autocmd BufEnter FileType sh match bad_tilde /^[^#].*\zs\~/
"for now, that's whenever it isn't in a comment. This isn't quite right yet though...

" highlight columns - highlight the 80th  column
let &colorcolumn="80"
highlight ColorColumn ctermbg=233
augroup vimrc_autocmds
  autocmd BufEnter * highlight OverLength ctermbg=darkgrey
  autocmd BufEnter c**,python,java match OverLength /\%80v.*/
augroup END

"""""""""""""""""""""""""""""""" abbreviations """"""""""""""""""""""""""""""""
" easy hashbangs
iabbrev #!b #!/usr/bin/env bash
iabbrev #!p #!/usr/bin/env python
iabbrev #!s #!/usr/bin/env sh

" easy printing in java
iabbr sop System.out.println("");<esc>2hi

"""""""""""""""""""""""""""""""""""" remap """"""""""""""""""""""""""""""""""""
" http://vim.wikia.com/wiki/Mapping_keys_in_Vim_-_Tutorial_(Part_1)

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

" in visual mode, use forward slash + <U> or <C> to <Un>Comment selection
vnoremap /c :norm 0i//<CR>
vnoremap /u :norm 2x<CR>

" source my vimrc/current file - useful for testing
nnoremap <Leader>sv :source ~/.vimrc<CR>
nnoremap <Leader>so :source %<CR>

" go to the next/prev item in the quickfix list
nnoremap <Leader>q :cnext<CR>
nnoremap <Leader>Q :cprev<CR>

" Insert the date in normal mode. Kiiiinda useless. But fun?
nnoremap <Leader>da :pu=strftime('%c')<CR>

""""""""""""" buffers/tabs """""""""""""
" Remove buffer from memory without closing window
nnoremap <Leader>bd :bnext\|bdelete #<CR>

" easily switch between buffers and tabs
nnoremap [b :bprevious<CR>
nnoremap ]b :bnext<CR>
nnoremap gr gT

""""""""""""""" movement """""""""""""""
nnoremap <Up> <C-y>k
nnoremap <Down> <C-e>j
map <Left> <Nop>
map <Right> <Nop>

"""""""""""""""" source """"""""""""""""
""""""" (library functions) """"""""
" returns the char that your cursor is over
" optional argument allows you to look at a char forward or backwards
function! CurChar(...)
  let a:offset = get(a:, 1, 0)
  return getline('.')[col('.') - 1 + a:offset]
endfunction

"""""""""" other files """""""""
source $HOME/.vim/pair.vim
source $HOME/.vim/tabs.vim
source $HOME/.vim/quickfix.vim

"""""""""""""""" other """"""""""""""""
" exit insert mode with 'jj<Space>'
inoremap jj <ESC>

" sessions
nmap <Leader>ss :wa<CR>:mksession! ~/.vim/sessions/
nmap <Leader>sess :wa<CR>:so ~/.vim/sessions/

" enable omnicompletion
set omnifunc=syntaxcomplete#Complete


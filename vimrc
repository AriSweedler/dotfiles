""""""""""""""""""""""""""""""""""" settings """"""""""""""""""""""""""""""""""
filetype on 			"allow for autocmds to be run based on filetype
colorscheme desert 		"pretty colors
set display=lastline 		"as much as possible of the last line will be displayed
set gdefault 			"turn global flag on by default for :substitute
set history=1000 		"the default is only 40.
set nocompatible 		"don't do weird stuff for backwards compatibility with vim
set number 			"turn on line numbers
set showcmd 			"multi-keystroke commands will be shown in bottom right.
set showmode 			"show vim mode in bottom left

" for more information, run `:help 'backspace'` (With `'`s - NOT `:help backspace`)
set backspace=indent,eol,start 	"allow backspacing over more things

" Nicer <Tab>'ing
set wildmenu
set wildmode=full

" ctags is so helpful! And easy, too. 
set tags+=tags;

" Toggle 'list' to show whitespace characters
set listchars=tab:▸\ ,space:·,eol:¬,

"""""""""""""""""""""""""""""""""""" other """"""""""""""""""""""""""""""""""""

" write file upon leaving a buffer
autocmd BufLeave,FocusLost * w

" Tab stuff. For more info, look to
" https://medium.com/@arisweedler/tab-settings-in-vim-1ea0863c5990
autocmd FileType c**,python setlocal tabstop=4 shiftwidth=4 softtabstop=4 expandtab
autocmd Filetype c** setlocal cindent foldmethod=syntax textwidth=80
autocmd FileType make* setlocal tabstop=8 shiftwidth=8 noexpandtab

"""""""""""""""""""""""""""""""" pretty colors """"""""""""""""""""""""""""""""
" Look at colors: http://vim.wikia.com/wiki/Xterm256_color_names_for_console_Vim

"""""""""""" color settings """"""""""""
syntax on 			"allow for syntax highlighting and indenting
set hlsearch 			"highlight search
set incsearch 			"incremental search - show where hitting enter WOULD place you
set showmatch matchtime=1 	"briefly show the matching {/[/( when typing )/]/}

"""""""""""" color commands """"""""""""
" highlight all trailing whitespace in C, python, or make
autocmd FileType c**,python,make* match trailing_whitespace /\s\+$/
highlight trailing_whitespace ctermbg=red

" highlight columns. This makes it look like the screen is broken lol. but it's nice
let &colorcolumn="80,".join(range(120,125),",")
highlight ColorColumn ctermbg=233


"""""""""""""""""""""""""""""""""""" remap """"""""""""""""""""""""""""""""""""
" http://vim.wikia.com/wiki/Mapping_keys_in_Vim_-_Tutorial_(Part_1)

"""""""""""""""" macros """"""""""""""""
" Control+underscore clears highlighting (doesn't turn off, just clears!)
noremap <C-_> :nohlsearch<CR>

" Save a file as root (\W)
noremap <Leader>WW :w !sudo tee % > /dev/null<CR>

" highlight most recently pasted code
nnoremap <Leader>= `[=`]

" sort CSS properties
nnoremap <Leader>S viB:sort<CR>

" quickly make an edit to my ~/.vimrc
nnoremap <Leader>ev :vsp $MYVIMRC<CR>

" use star in visual mode to search for the selected text
" yank into register s --> forward search for the contents of register s
" (Very nomagic, escape contents of s register before pasting)
vnoremap * "sy/\V<C-R>=escape(@s, '/\')<CR><CR>N

""""""""""""" buffers/tabs """""""""""""
" Delete buffer without closing window
nnoremap <Leader>bd :bnext\|bdelete #<CR>

" easily switch between buffers (and also tabs)
nnoremap [b :bprevious<CR>
nnoremap ]b :bnext<CR>
nnoremap gr gT

""""""""""""""" movement """""""""""""""
" Go to matching bracket with tab in visual/normal mode using <Tab>
nnoremap <Tab> %
vnoremap <Tab> %

" Nicer file traversing
nnoremap <Up> <C-y>k
nnoremap <Down> <C-e>j

" no need to use these
map <Left> <Nop>
map <Right> <Nop>

"""""""""""""""" other """"""""""""""""
" exit insert mode with 'jj'
inoremap jj <ESC>


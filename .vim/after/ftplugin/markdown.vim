runtime after/ftplugin/text.vim

" Set folding for 3-backtick markdown divider block
set foldmethod=marker foldmarker={{{,}}}

" TODO check to see if we're in one of the "notes" directories
" Invoke auto-loadable init function for notes
" Here it is for gf: ~/.vim/autoload/notes.vim
call notes#init()

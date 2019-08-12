runtime ftplugin/text.vim

" Set folding for 3-backtick markdown divider block
set foldmethod=marker foldmarker=```block,```
iabbrev codeblock ```block<CR>```<C-c>kA

" TODO: Make a syntax construct where spelling is ignored? Useful for ascii
" diagrams or whatever. ``` is mostly good enough

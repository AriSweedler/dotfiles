highlight Conceal ctermfg=15 ctermbg=90

" It would be cool if I could run a callback on the start of highlighting a
" region, and another one upon ending. But alas, it is not so simple.
"
" My goal would be to have ALL of the markdownHighlightC region be highlighted
" with the background, and all the C highlights would have that background, too,
" unless they specified their own background
"
" Perhaps the way to do this would actually be to run
" `highlight GROUP <EXISTING GROUP> ctermbg=240` on each of the C code things
"
" For example, I could read the highlight group of `cString` and produce
" `highlight cString ctermbg=240 ctermfg=117`
highlight markdownCodeBlock ctermbg=240
highlight markdownHighlightC ctermbg=240

let g:markdown_fenced_languages = ["bash", "sh"]

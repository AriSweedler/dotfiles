syntax case ignore

syntax keyword mdTodo TODO
highlight def link mdTodo Todo

syntax region notesTodo start=/DO/ end=/!$/ oneline
highlight notesTodo term=standout ctermfg=10

syntax keyword mdDone DONE
highlight mdDone cterm=bold ctermfg=6

syntax match UConfidence /unshakeable\_sconfidence/
syntax match AConfidence /adaptable\_sconfidence/
highlight UConfidence term=standout ctermfg=2
highlight AConfidence term=standout ctermfg=10

syntax case match

" Conceal markdown links
syntax match markdownUrl "\S\+" nextgroup=markdownUrlTitle skipwhite contained conceal cchar=x
highlight Conceal ctermfg=14 ctermbg=242
setlocal nowrap
setlocal conceallevel=2
setlocal concealcursor=nc

" TODO what of this belongs in a syntax file and what belongs in the ftplugin
" file? Learn the semantic differences and make moves based off of that.
" TODO should I split the syntax commands and the highlight commands? Figure out
" best practices here.

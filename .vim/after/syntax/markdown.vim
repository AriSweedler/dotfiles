syntax case ignore

syntax keyword mdTodo TODO
highlight def link mdTodo Todo

syntax region notesTodo start=/DO/ end=/!$/ oneline
syntax region notesBackburner start=/Backburner/ end=/!$/ oneline
syntax region notesDone start=/DONE/ end=/!$/ oneline contains=mdDone
highlight notesTodo term=standout ctermfg=10
highlight notesBackburner term=standout ctermfg=64
highlight notesDone term=standout ctermfg=6

syntax match UConfidence /unshakeable\_sconfidence/
syntax match AConfidence /adaptable\_sconfidence/
highlight UConfidence term=standout ctermfg=2
highlight AConfidence term=standout ctermfg=10

syntax case match

" Conceal markdown links
syntax match markdownUrl "\S\+" nextgroup=markdownUrlTitle skipwhite contained conceal cchar=x
highlight Conceal ctermfg=15 ctermbg=90
setlocal nowrap
setlocal conceallevel=2
setlocal concealcursor=nc

" TODO what of this belongs in a syntax file and what belongs in the ftplugin
" file? Learn the semantic differences and make moves based off of that.
" TODO should I split the syntax commands and the highlight commands? Figure out
" best practices here.

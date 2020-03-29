" Syntax matches where case doesn't matter go below here (until we turn case
" matching back on with 'syntax case match')
syntax case ignore

" Useful TODO keyword
syntax keyword mdTodo TODO
highlight def link mdTodo Todo

syntax case match
" Syntax matches where case matters go below

" TODO make this better - it has to be part of a bulleted list
"   * <Urgency> <Description> - <mm>/<dd> (due in <days> days) !
syntax region notesTodo start=/DO/ end=/!$/ oneline contains=markdownLinkText
syntax region notesBackburner start=/Backburner/ end=/!$/ oneline
syntax region notesDone start=/DONE/ end=/!$/ oneline contains=markdownLinkText
highlight notesTodo term=standout ctermfg=10
highlight notesBackburner term=standout ctermfg=238
highlight notesDone term=standout ctermfg=23

" Specially highlight Log lines. They're of the form:
" {<logCategory>: <logDescription>}
" Anything that has an imdb link goes under 'Movie', for now
syntax region logLine start=/^{[^{]/ end=/}$/ keepend oneline contains=logCategory,logDescription
syntax keyword logCategory contained Chore Movie Workout Blog Drug Video
syntax match logDescription /:\zs.*\ze.$/ contained
" TODO make the logDescription pattern better somehow?
highlight logLine term=standout ctermfg=7
highlight logCategory ctermfg=27
highlight logDescription ctermfg=133

" Conceal markdown links (make it more Browser-y)
syntax match markdownUrl "\S\+" nextgroup=markdownUrlTitle skipwhite contained conceal cchar=x
highlight Conceal ctermfg=15 ctermbg=90

" TODO: should I split the syntax commands and the highlight commands? Figure out
" best practices here.
"
" TODO: Write syntax highlighting to highlight the Headers of folds a certain
" color

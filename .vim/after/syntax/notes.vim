"""""""""""""""""""""" Syntax file for 'notes' filetype """"""""""""""""""""""
""""""""""""""""""""""" syntax & highlight group links """"""""""""""""""""{{{
" {{{ Fold
syntax match notesNamedFoldStart +^{{{+ nextgroup=notesNamedFoldHeader,notesLogStart
syntax match notesNamedFoldHeader +[^!]*+ contained containedin=NONE
" {{{ fold-marker is not as good as fold-syntax when the marker is data :c
syntax region notesNamedFoldBodyNospell start=+!@+ matchgroup=notesNamedFoldEnd end=+^}}}+ contains=@NoSpell
syntax match notesNamedFoldEnd +^}}}+

highlight link notesNamedFoldStart notesNamedFoldBracket
highlight link notesNamedFoldHeader notesHeader
highlight link notesNamedFoldEnd notesNamedFoldBracket
" }}}
" {{{Log header
syntax match notesLogStart + {[^:]*+ contained containedin=NONE nextgroup=notesLogDescription
syntax keyword notesLogType Blog Book Chore Drug Movie Workout Video contained containedin=notesLogStart
syntax match notesLogDescription +[^}]*+ contained containedin=NONE nextgroup=notesLogEnd contains=@NoSpell
syntax match notesLogEnd +}+ contained containedin=NONE

highlight link notesLogStart notesLogBrackets
highlight link notesLogType notesHeader
highlight link notesLogDescription notesSubheader
highlight link notesLogEnd notesLogBrackets
"}}}
" {{{ Define the "TODO" keyword
syntax case ignore
syntax keyword notesTodo TODO
syntax case match
" }}}
" {{{ Links
"TODO rewrite this guy so we can have a top-level link object with 2 kids - text and URL
syntax cluster notesLink contains=notesLinkText
" Literal [
" THEN 0-width: zero-or-more of 'NOT ]'
" THEN 0-width: Literal ](
syntax region notesLinkText matchgroup=notesLinkTextDelimiter start=+\[\%(\_[^]]*](\)\@=+ matchgroup=notesLinkTextDelimiter end=+]+ nextgroup=notesLinkURL
syntax region notesLinkURL matchgroup=notesLinkTextDelimiter start=+(+ matchgroup=notesLinkTextDelimiter end=+\%()\|\_s\)+ contained containedin=NONE contains=@NoSpell conceal
highlight link notesLinkTextDelimiter notesLinkDelimiter
highlight link notesLinkText String
" }}}
" {{{ Priority for notesListMarker
syntax region notesListItem transparent matchgroup=notesListMarker start="^\s*[-*+]\%(\s\S\)\@=" end="$" keepend contains=@notesTodoListSpecialItems,@notesLink
highlight link notesListMarker notesBullet

" Special items in the list
syntax cluster notesTodoList contains=@notesListItem,@notesTodoListSpecialItems
syntax cluster notesTodoListSpecialItems contains=notesTodoListDO,notesTodoListDONE,notesTodoListBackburner
syntax region notesTodoListDO start=/DO/ end=/!$/ oneline contains=@NoSpell,@notesLink contained
syntax region notesTodoListDONE start=/DONE/ end=/!$/ oneline contains=@NoSpell,@notesLink contained
syntax region notesTodoListBackburner start=/Backburner/ end=/!$/ oneline contains=@NoSpell,@notesLink contained
highlight link notesTodoListDO notesDO
highlight link notesTodoListDONE notesDONE
highlight link notesTodoListBackburner notesBackburner
" }}}
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}

""""""""""""""" Colorscheme (give colors to the linked groups) """"""""""""{{{
highlight notesHeader term=bold ctermfg=5
highlight notesSubheader term=bold ctermfg=61
highlight notesNamedFoldBracket ctermfg=89
highlight notesLogBrackets term=bold ctermfg=80
highlight link notesTodo Todo
highlight notesBullet ctermfg=3
highlight notesDO term=standout ctermfg=10
highlight notesDONE term=standout ctermfg=23
highlight notesBackburner term=standout ctermfg=238
highlight notesLinkDelimiter ctermfg=17
highlight notesLinkURL ctermfg=54

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}

echom printf("[%s] Notes syntax file sourced", expand('%'))
finish

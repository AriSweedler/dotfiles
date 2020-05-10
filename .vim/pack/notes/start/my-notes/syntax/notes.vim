"""""""""""""""""""""" Syntax file for 'notes' filetype """"""""""""""""""""""
if exists("b:current_syntax")
  finish
endif

""""""""""""""""""""""" syntax & highlight group links """"""""""""""""""""{{{
" {{{ Fold
syntax match notesNamedFoldStart +^{{{+ nextgroup=notesNamedFoldHeader,notesLogStart
syntax match notesNamedFoldHeader +[^!]*+ contained containedin=NONE contains=@NoSpell
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
highlight link notesLinkTextDelimiter notesDelimiterHidden
highlight link notesLinkText Underlined
" }}}
" {{{ Priority for notesListMarker
syntax region notesListItem transparent matchgroup=notesListMarker start="^\s*[-*+]\%(\s\S\)\@=" end="$" keepend contains=@notesText
highlight link notesListMarker notesBullet

" Special items in the list
syntax cluster notesBangList contains=@notesListItem,@notesBangListSpecialItems
syntax cluster notesBangListSpecialItems contains=notesBangListDO,notesBangListDONE,notesBangListBackburner
syntax region notesBangListDO start=/DO\>/ end=/!$/ oneline contains=@NoSpell,@notesText contained
syntax region notesBangListDONE start=/DONE\>/ end=/!$/ oneline contains=@NoSpell,@notesText contained
syntax region notesBangListBackburner start=/Backburner\>/ end=/!$/ oneline contains=@NoSpell,@notesText contained

highlight link notesBangListDO notesDO
highlight link notesBangListDONE notesDONE
highlight link notesBangListBackburner notesBackburner
" }}}
" {{{ Italics/Bold/literals
syntax region notesItalic matchgroup=notesItalicDelimiter start="\*\%(\S\)\@=" matchgroup=notesItalicDelimiter end="\%(\S\)\@<=\*" keepend concealends
syntax region notesBold matchgroup=notesBoldDelimiter start="\*\*\%(\S\)\@=" matchgroup=notesBoldDelimiter end="\%(\S\)\@<=\*\*" keepend concealends
syntax region notesCodeLiteral matchgroup=notesCodeLiteralDelimiter start="`\%(\S\)\@=" matchgroup=notesCodeLiteralDelimiter end="\%(\S\)\@<=`" keepend concealends
syntax region notesBar matchgroup=notesBarDelimiter start="|\%(\S\)\@=" matchgroup=notesBarDelimiter end="\%(\S\)\@<=|" keepend concealends
syntax cluster notesWeightedTextDelimiter contains=notesItalicDelimiter,notesBoldDelimiter,notesCodeLiteralDelimiter,notesBarDelimiter
syntax cluster notesWeightedText contains=notesItalic,notesBold,notesCodeLiteral,notesBar,@notesWeightedTextDelimiter

highlight notesItalic cterm=italic
highlight notesBold cterm=bold
highlight notesCodeLiteral ctermbg=240
highlight notesBar cterm=underline ctermfg=20

highlight notesItalicDelimiter ctermfg=22
highlight notesBoldDelimiter ctermfg=27
" }}}
syntax cluster notesText contains=@notesBangListSpecialItems,@notesLink,@notesWeightedText
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
highlight notesDelimiterHidden ctermfg=17
highlight notesDelimiterStandout ctermfg=5
highlight notesLinkURL ctermfg=54
highlight link notesCodeLiteralDelimiter notesDelimiterStandout
highlight link notesBarDelimiter notesDelimiterHidden

" TODO 22 is a beautiful green color. Can I use it somewhere?
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}

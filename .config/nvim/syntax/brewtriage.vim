" A `dotfiles brew triage --edit` plan: `<action>  <kind:name>  [# reason]` per line, # comments.
if exists("b:current_syntax")
  finish
endif

syntax match brewtriageComment /#.*$/ contains=@Spell
syntax match brewtriageItem /\<\%(formula\|cask\|tap\|vscode\):\S\+/ contained
syntax match brewtriageAction /^\s*\%(global\|local\)\s\+\%(add\|ignore\)\>/ nextgroup=brewtriageItem skipwhite
syntax match brewtriageDelete /^\s*delete\>/ nextgroup=brewtriageItem skipwhite
syntax match brewtriageSkip /^\s*skip\>/ nextgroup=brewtriageItem skipwhite

highlight default link brewtriageComment Comment
highlight default link brewtriageItem Keyword
highlight default link brewtriageAction Type
highlight default link brewtriageDelete Error
highlight default link brewtriageSkip NonText

setlocal commentstring=#\ %s
let b:current_syntax = "brewtriage"

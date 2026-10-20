" Every `dotfiles … --edit` plan (lib/plan.zsh): `<action>  <item>  [# note]` per line, # comments.
" Line 1, `# dotfiles-plan: KIND · actions: a | b c | … · danger: x`, names the actions, so a plan
" type added later is highlighted with no change here. Without it, the actions the harness uses.
if exists("b:current_syntax")
  finish
endif

let s:head = getline(1)
if s:head =~# '^# dotfiles-plan:'
  let s:actions = map(split(matchstr(s:head, 'actions: \zs[^·]*'), '|'), 'trim(v:val)')
  let s:danger = map(split(matchstr(s:head, 'danger: \zs[^·]*'), '|'), 'trim(v:val)')
else
  let s:actions = ['global add', 'local add', 'global ignore', 'local ignore', 'delete', 'apply', 'push', 'commit', 'restore', 'skip']
  let s:danger = ['delete', 'restore']
endif

syntax match dotfilesplanComment /#.*$/ contains=@Spell
syntax match dotfilesplanItem /\S\+/ contained
for s:action in s:actions
  let s:group = index(s:danger, s:action) >= 0 ? 'dotfilesplanDanger' : (s:action ==# 'skip' ? 'dotfilesplanSkip' : 'dotfilesplanAction')
  execute 'syntax match ' . s:group . ' /^\s*\V' . escape(s:action, '/\') . '\m\>/ nextgroup=dotfilesplanItem skipwhite'
endfor

highlight default link dotfilesplanComment Comment
highlight default link dotfilesplanItem Keyword
highlight default link dotfilesplanAction Type
highlight default link dotfilesplanDanger Error
highlight default link dotfilesplanSkip NonText

setlocal commentstring=#\ %s
let b:current_syntax = "dotfilesplan"

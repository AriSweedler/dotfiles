syn keyword	mdTodo		TODO
hi def link mdTodo		Todo


syntax case ignore
syntax match UConfidence /unshakeable\_sconfidence/
syntax match AConfidence /adaptable\_sconfidence/
syntax case match
highlight UConfidence term=standout ctermfg=2
highlight AConfidence term=standout ctermfg=10

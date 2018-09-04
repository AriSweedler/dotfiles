""inoremap { <C-r>=OpenBrace('{', '}')<CR>
""inoremap ( <C-r>=OpenBrace('(', ')')<CR>
""inoremap [ <C-r>=OpenBrace('[', ']')<CR>

""function! CloseBrace(open, close)
  ""if CurChar() == a:open
    ""return "\<Right>"
  ""endif
""endfunction
""
echo "brackets.vim sourced"


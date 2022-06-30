" Enable syntax, and set a colorscheme. Don't do this twice
if !exists("colors_name")
  syntax enable       "allow for syntax highlighting and indenting
  colorscheme slate   "pretty colors
endif

" Highlight the lines that folds create when folded
highlight Folded ctermbg=234 ctermfg=8

" Give fun colors to the left columns (and the ColorColumn)
highlight FoldColumn ctermbg=233 ctermfg=8
highlight SignColumn ctermbg=234 ctermfg=8
highlight ColorColumn ctermbg=233

" Diff colors
highlight DiffAdd        ctermbg=22
highlight DiffChange     ctermbg=178 cterm=bold
highlight DiffDelete     ctermbg=124 ctermfg=1
highlight DiffText       term=reverse cterm=bold ctermbg=1

" I just prefer this for 'slate'
highlight clear MatchParen
highlight link MatchParen IncSearch

" Toggle syntax highlighting
noremap <Leader>sy :call lib#toggleSyntax()<CR>

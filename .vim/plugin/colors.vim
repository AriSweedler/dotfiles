" Enable syntax, and set a colorscheme. Don't do this twice
if !exists("colors_name")
  syntax enable       "allow for syntax highlighting and indenting
  colorscheme slate   "pretty colors
endif

" Diff colors
highlight DiffDelete     ctermbg=124 ctermfg=9
highlight DiffAdd        ctermbg=22 ctermfg=2
highlight DiffChange     ctermbg=178 ctermfg=3
highlight DiffText       term=reverse cterm=bold ctermbg=1

" I like this bright green for MatchParens
highlight MatchParen ctermfg=16 ctermbg=22

" And I wanna show off the current line's number
highlight LineNr term=underline ctermfg=3
highlight LineNrAbove term=underline ctermfg=8
highlight link LineNrBelow LineNrAbove

" Comments should stick out slightly more than 'slate' makes them
highlight Comment term=bold ctermfg=66

" Toggle syntax highlighting
noremap <Leader>sy :call lib#toggleSyntax()<CR>

" Need to call a few functions to reload colors. Collect them here
command ColorsReload :call <SID>Reload()
function! s:Reload()
  StatuslineReload
  source ~/.vim/plugin/config/gitgutter.vim
endfunction

" https://github.com/vim/vim/issues/10449
" Transparent background (for tmux inactive panes)
highlight Normal ctermbg=NONE

" The tildes at the end of a buffer
highlight EndOfBuffer ctermfg=33 ctermbg=NONE
highlight WinSeparator ctermbg=53 ctermfg=53

" Highlight the lines that folds create when folded
highlight Folded ctermbg=234 ctermfg=8

" Give fun colors to the left columns (and the ColorColumn)
highlight FoldColumn ctermbg=233 ctermfg=8
highlight SignColumn ctermbg=234 ctermfg=8
highlight ColorColumn ctermbg=233

" ??? Why did these go away? Fking neovim.
highlight String ctermfg=208
highlight Constant ctermfg=172
highlight Special ctermfg=200
highlight Type cterm=bold ctermfg=40
highlight Statement cterm=NONE ctermfg=184
highlight PreProc cterm=NONE ctermfg=127
highlight Directory cterm=bold ctermfg=25
highlight Title ctermfg=13
highlight Underlined ctermfg=129
highlight CursorLine ctermbg=240 ctermfg=NONE
highlight CursorLineNr ctermfg=3 ctermbg=240
highlight CursorLineSign ctermbg=238
highlight CursorLineFold ctermbg=3 ctermfg=3
highlight Visual ctermbg=22
highlight IncSearch ctermbg=12 ctermfg=7
highlight Operator ctermfg=130
highlight Function cterm=bold ctermfg=38
highlight Structure ctermfg=2
highlight Question ctermfg=10
highlight MoreMsg ctermfg=22
highlight TabLine ctermfg=230 ctermbg=237
highlight TabLineSel cterm=bold ctermfg=230 ctermbg=25
highlight TabLineFill ctermbg=NONE
highlight Error cterm=NONE ctermfg=7 ctermbg=9

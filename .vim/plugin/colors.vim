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
highlight clear LineNrAbove
highlight clear LineNrBelow
highlight LineNrAbove term=underline ctermfg=8
highlight link LineNrBelow LineNrAbove

" Comments should stick out slightly more than 'slate' makes them
highlight Comment term=bold ctermfg=66

" Toggle syntax highlighting
noremap <Leader>sy :call lib#toggleSyntax()<CR>

command ColorsReload :call <SID>Reload()
function! s:Reload()
  StatuslineReload
  source ~/.vim/plugin/config/gitgutter.vim
endfunction

" https://github.com/vim/vim/issues/10449
" Transparent background (for tmux inactive panes)
highlight Normal ctermbg=NONE

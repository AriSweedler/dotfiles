let g:fzf_commits_log_options = '--graph --color=always --format="%C(auto)%h%d %s %C(green)%C(bold)%cr" --follow'
command! -bang HawkFiles call fzf#vim#files('~/Desktop/source/hawkeye/', <bang>0)
" Arg is a command string OR a list. This can be used to autocomplete something
" from a personal dictionary
" inoremap <expr> <c-x><c-k> fzf#vim#complete('cat /usr/share/dict/words')

set rtp+=/usr/local/opt/fzf
source /usr/local/opt/fzf/plugin/fzf.vim

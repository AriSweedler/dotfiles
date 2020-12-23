setlocal tabstop=2 expandtab
set nospell

set foldmethod=marker

" I find myself doing this a lot for some reason.
map <Leader><Leader><Leader> /\cLeader<CR>

nnoremap <Leader>f 0xx$xxA {{{<C-c>
nnoremap <Leader>F 0xx$xxA }}}<C-c>

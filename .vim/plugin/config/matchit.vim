" The first time we invoke '%', load the matchit plugin. Don't need to try and
" load it every time lol, so unmap it after we do it once.
nnoremap <silent> % :packadd matchit <Bar> unmap %<CR>%

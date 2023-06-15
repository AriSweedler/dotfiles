nnoremap gb :Git blame<CR>
nnoremap gD :vertical Gdiffsplit dev<CR>
" You have to manually hit <CR> for 'gH' - it gives you the option to type a
" number, or even some other ref out
nnoremap gH :vertical Gdiffsplit HEAD~

highlight diffAdded ctermfg=green

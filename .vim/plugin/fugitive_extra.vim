" From dhruvasagar:
" https://github.com/dhruvasagar/dotfiles/blob/master/vim/plugin/fugitive_extra.vim

function! s:toggle_gstatus()
  for l:winnr in range(1, winnr('$'))
    if !empty(getwinvar(l:winnr, 'fugitive_status'))
      execute l:winnr.'close'
      return
    endif
  endfor
  Git
endfunction

" Commands and Mappings
" TODO find the best mapping to toggle gstatus
nnoremap <Leader>gg :call <SID>toggle_gstatus()<CR>
nnoremap <Leader>gs :call <SID>toggle_gstatus()<CR>
nnoremap <Leader>gS :call <SID>toggle_gstatus()<CR>
nnoremap <Leader>gP :Git push<CR>
nnoremap <Leader>gC :Git commit<CR>

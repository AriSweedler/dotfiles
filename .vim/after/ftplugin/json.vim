setlocal tabstop=2 expandtab
setlocal foldmethod=syntax

" Help compare JSON files
nnoremap <Leader><Leader><C-d> :call DiffMode()
nmap <Leader><C-d> <Leader><Leader><C-d><C-w><C-w><Leader><Leader><C-d><C-w><C-w>
function DiffMode()
  " Format the file with jq
  %!jq
  write

  " enter 'diff' mode
  diffthis

  " Set up convenient keymappings to jump through the files
  nnoremap <buffer> <C-p> [czz
  nnoremap <buffer> <C-n> ]czz
endfunction


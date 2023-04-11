setlocal tabstop=2 expandtab
setlocal foldmethod=syntax

" Help compare JSON files
nnoremap <Leader><Leader><C-d> :call DiffMode()<Enter>
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

" Format key/values where the value is a JSON string (instead of a json
" object, as it SHOULD be...). This us useful for when we have an HTTP POST
" req as a JSON object, and the POST body is a string. We know we can format
" it as json, but gotta translate it first...

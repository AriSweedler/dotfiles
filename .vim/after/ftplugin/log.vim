" Search for UUIDs
nnoremap <buffer> <Leader>u /\x\{8}-\x\{4}-\x\{4}-\x\{4}-\x\{12}<CR>

" <Leader>f to set the command we wanna fetch with
" <Leader>F to execute the fetch and reload the current buffer
let b:fetch_log_cmd = ""
nnoremap <buffer> <Leader>r :let b:fetch_log_cmd = "!FILLMEOUT"
nnoremap <buffer> <Leader>R :execute b:fetch_log_cmd<CR>:edit! %<CR>

" For HIT logs...
" setlocal conceallevel=3
setlocal foldmethod=marker

" Better dealing with escape codes
syntax match LogANSIEscapeCode /\[[0-9]\+\(;[0-9]\+\)*m/ conceal
highlight link LogANSIEscapeCode error
nnoremap <Leader>fC :call <SID>strip_ansi_codes()<CR>
function s:strip_ansi_codes()
  :%substitute/\[[0-9]\+\(;[0-9]\+\)*m//g
endfunction

" Special-case log filtering commands
nnoremap <buffer> <Leader>f? :nnoremap <Leader>f<Enter>
nnoremap <buffer> <Leader>fD :%!awk '/DEBUG.*{{{/,/}}}/ {next} /DEBUG/ {next} {print}'<Enter>
nnoremap <buffer> <Leader>fR :%!prettier --parser ruby<Enter>
nnoremap <buffer> <Leader>fU :%!ult filter 2>/dev/null<Enter>
nnoremap <buffer> <Leader>fO :%!ult filter cmd_output 2>/dev/null<Enter>

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" {{{
""""""""""""""""""""""""""""" Initialize notes """"""""""""""""""""""""""""" {{{
" TODO how do other plugins init themselves?
function! notes#init()
  "echom "NOTES INIT AUTOLOAD FUNCTION SOURCED!"

  " This allows links to be displayed prettier
  setlocal nowrap
  setlocal conceallevel=2
  setlocal concealcursor=nc

  nnoremap gx :call notes#OpenLink()<CR>

  command! UpdateDates global/(in \d* days) !/normal dgn$h\1A !<C-_>

  " Remap <bang> to mark or toggle DO/DONE
  nnoremap ! :call notes#banglist#controller()<CR>
  nnoremap <Leader>! :call notes#banglist#controller('DO')<CR>
  nnoremap ? :call notes#banglist#toggle_backburner_highlight()<CR>
  nnoremap <Leader>? :call notes#banglist#controller('DO', 'Backburner')<CR>

  command! DoneBeGone keeppatterns g/[!*] DONE/d

  nnoremap <Leader>y :<C-u>call notes#Yesterday_Helper('edit', v:count)<CR>
  "<Bar> Foldo <C-r>=g:notes_foldo<CR><CR>
  nnoremap <Leader><Leader>y :<C-u>call notes#Yesterday_Helper('edit', -1*v:count)<CR>
  "<Bar> Foldo <C-r>=g:notes_foldo<CR><CR>

  " Foldo command to open a named fold
  command! -nargs=1 Foldo let g:notes_foldo = <q-args> <Bar> keeppatterns silent g/\c^{\{3,3} <args>/normal zx
  nnoremap <Leader><Leader>F :Foldo
  nnoremap <Leader>FC :Foldo Classes<CR>
  nnoremap <Leader>FV :Foldo Vim<CR>
  nnoremap <Leader>FT :Foldo TODOs<CR>

  " Change curly quotes into regular quotes and stuff
  command! FixPastedPDF keeppatterns call notes#FixPastedPDF()
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""""""""" Links """""""""""""""""""""""""""""""""" {{{
" Open the URL under cursor. Or the last link on the line
" Links are of the form [title](URL)
function! notes#OpenLink()
  " Try to find link under cursor
  let l:link_regex = '\[\_[^]]*](\([^)\_s]\{-}\))'
  let l:link = substitute(expand('<cWORD>'), l:link_regex, '\1', '')

  " If no substitution is made, no link was found.
  " Try to find last link on the current line
  if l:link == expand('<cWORD>')
    echom "No link under cursor. Trying to open last link on this line"
    let l:line_link_regex = '^.*' . l:link_regex . '.*$'
    let l:link = substitute(getline('.'), l:line_link_regex, '\1', '')
  endif

  " If no substitution is made, no link was found.
  if l:link == getline('.')
    echom "ERROR: No link found on this line. Giving up"
    return
  endif

  execute '!open "' . l:link . '"'
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""""""" Yesterday """""""""""""""""""""""""""""""" {{{
" Open up Yesterday's notes file. Take the n'th line from the end in our
" .daykeeper file and open that up
function! notes#Yesterday_Helper(open_method, ...)
  " Get the 1st optional argument (default to 1 if no value provided)
  let days_ago = get(a:, 1, 1)
  if days_ago == 0
    let days_ago = 1
  endif

  " Get the line number in the daykeeper file
  let daykeeper_line = expand("%:.:r")->substitute("/", "\\\\/", "")
  let command = 'sed -n "/' . l:daykeeper_line . '/=" .daykeeper'
  let absoltue_day = system(l:command)
  let desired_day = l:absoltue_day - l:days_ago
  if l:desired_day <= 0
    let l:desired_day = 1
  endif

  " Create a command to get the file from <days_ago> days ago (must strip
  " trailing newline)
  let command = "head -" . l:desired_day. " .daykeeper | tail -1 | tr -d '\n'"
  let file = system(l:command) . "*"

  " open up the file
  execute a:open_method . " " . l:file

  if exists("g:notes_foldo")
    execute 'Foldo ' . g:notes_foldo
  endif
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""" Copy Named Folds """"""""""""""""""""""""""""" {{{
function! notes#GetNamedFold(pattern)
  execute 'wincmd w'
  let temp = &foldlevel
  set foldlevel=10
  execute 'silent keeppatterns global/^{\{3,3} ' . a:pattern . '/normal Va{"0y'
  execute 'set foldlevel=' . temp
  execute 'wincmd w'
  .put 0
endfunction
nnoremap <Leader>T :call notes#GetNamedFold('TODOs') <Bar> DoneBeGone<CR>:Foldo Classes<CR>
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""" For copy/pasting from PDFs """""""""""""""""""""""" {{{
" For copy/pasting that BS
function! notes#FixPastedPDF()
  %substitute/â/-/e
  %substitute/â/'/e
  %substitute/â/"/e
  %substitute/â/"/e
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}

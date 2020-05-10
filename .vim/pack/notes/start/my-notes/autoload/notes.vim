" TODO how do other plugins init themselves?
" fugitive has 1 plugin file (automatically loaded) and it defines
" 1) INCLUDE GUARDS
" 2) some functions
" 3) some vars (s, not g)
" 4) augroup
" 5) some commands
" """
" gitgutter also has only 1 plugin file
" 1) Default mappings
" 2) Default commands
" 3) augroup
" 4) INCLUDE GUARDS
" Conclusion:
" plugin -   I should have 1 and only 1 plugin file (of the same name as my plugin itself)
"             This file should set up default mappings (politely/not
"             overwritingly) and commands and the 100% needed functions
" docs -     I should have docs file
" autoload - I should have most of my code in autoload. Split into different
"             folders and files at a reasonable level (Proably each top-level
"             fold can be it's own file)
" syntax -   This is needed (TODO)
" ftdetect - This is also needed (TODO)
" tests -    A test folder if I want (I don't lol)
" gitignore, README, .github, license
"
"""""""""""""""""""""""""""""" notes autolaod """""""""""""""""""""""""""""" {{{
""""""""""""""""""""""""""""" Initialize notes """"""""""""""""""""""""""""" {{{
function! notes#init()
  " Remap <bang> to mark or toggle DO/DONE
  nnoremap ! :call notes#banglist#controller()<CR>
  nnoremap <Leader>! :call notes#banglist#controller('DO')<CR>
  nnoremap ? :call notes#banglist#toggle_backburner_highlight()<CR>
  nnoremap <Leader>? :call notes#banglist#controller('DO', 'Backburner')<CR>

  " Bring TODOs to today's file, delete DONE banglist items, open the Classes fold
  nnoremap <Leader>T :call notes#getNamedFold('TODOs') <Bar> call notes#banglist#global('DONE', 'delete') <Bar> FoldOpen Classes<CR>

  command! TYesterday call notes#yesterday#openHelper('tabedit', 1)
  " Go to yesterday (<Leader>y) or tomorrow (<Leader>Y). Takes a count.
  nnoremap <Leader>y :<C-u>call notes#yesterday#openHelper('edit', v:count)<CR>
  nnoremap <Leader>Y :<C-u>call notes#yesterday#openHelper('edit', -1*v:count)<CR>

  " Remap gx to my improved(?) function
  nnoremap gx :call notes#openLink()<CR>

  " FoldOpen commands
  command! -nargs=1 FoldOpen let g:notes_foldo = <q-args> <Bar> keeppatterns silent g/\c^{\{3,3} <args>/normal zx
  nnoremap <Leader><Leader>F :FoldOpen
  nnoremap <Leader>FC :FoldOpen Classes<CR>
  nnoremap <Leader>FV :FoldOpen Vim<CR>
  nnoremap <Leader>FT :FoldOpen TODOs<CR>

  " Change curly quotes into regular quotes and stuff
  command! FixPastedPDF keeppatterns call notes#fixPastedPDF()
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""""""""" Links """""""""""""""""""""""""""""""""" {{{
" Open the URL under cursor. Or the last link on the line
" Links are of the form [title](URL)
function! notes#openLink()
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
""""""""""""""""""""""""""""" Copy Named Folds """"""""""""""""""""""""""""" {{{
" Copy a named fold from the other window into register @0 then paste it
function! notes#getNamedFold(pattern)
  execute 'wincmd w'
  " Open folds in the other window so we can use `Va{` as intended
  let l:saved_foldlevel = &foldlevel
  let &foldlevel = 10
  execute 'silent keeppatterns global/^{\{3,3} ' . a:pattern . '/normal Va{"0y'
  let &foldlevel = l:saved_foldlevel
  execute 'wincmd w'
  .put 0
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""" For copy/pasting from PDFs """""""""""""""""""""""" {{{
" For copy/pasting that BS
function! notes#fixPastedPDF()
  %substitute/â/-/e
  %substitute/â/'/e
  %substitute/â/"/e
  %substitute/â/"/e
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}

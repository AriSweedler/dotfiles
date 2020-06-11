" TODO:
" 1) Add INCLUDE GUARDS where proper
" 2) Add DOCS
"""""""""""""""""""""""""""""" notes autolaod """""""""""""""""""""""""""""" {{{
""""""""""""""""""""""""""""" Initialize notes """"""""""""""""""""""""""""" {{{
" This is where I put all my default kepmappings. If I wanted to make this a
" real plugin, I would check to make sure I'm not overriding stuff first
function! notes#init()
  " Remap <bang> to mark or toggle DO/DONE
  nnoremap 1 :unlet g:lib#prev_cur_pos['banglist']<CR>
  nnoremap ! :call notes#banglist#controller()<CR>
  nnoremap <Leader>! :call notes#banglist#controller('DO')<CR>
  nnoremap ? :call notes#banglist#controller('DO', 'Backburner')<CR>
  nnoremap <Leader>? :call notes#banglist#toggle_backburner_highlight()<CR>

  " Bring TODOs to today's file, delete DONE banglist items, open the Classes fold
  nnoremap <Leader>T :call notes#getNamedFold('TODOs') <Bar> call notes#banglist#global('DONE', 'delete') <Bar> FoldOpen Classes<CR>

  command! TYesterday call notes#yesterday#openHelper('tabedit', 1)
  " Go to yesterday (<Leader>y) or tomorrow (<Leader>Y). Takes a count.
  nnoremap <Leader>y :<C-u>call notes#yesterday#openHelper('edit', v:count)<CR>
  nnoremap <Leader>Y :<C-u>call notes#yesterday#openHelper('edit', -1*v:count)<CR>
  nnoremap <Leader><Leader>y :<C-u>call notes#yesterday#openHelper('edit', v:count)<CR>

  " Give access to Today/Yesterday Commands to reset journal state
  command! NotesToday execute "edit " . system('tail -1 .daykeeper | tr -d "\n"') . ".*"
  command! NotesYesterday execute "edit " . system('tail -2 .daykeeper | head -1 | tr -d "\n"') . ".*"

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

  " Copy a link to a clipboard then invoke <C-k> to make a word say that
  inoremap <C-k> <C-c>diWa[<C-r>"](<C-r>0)
  nnoremap <C-k> diWa[<C-r>"](<C-r>0)
  vnoremap <C-k> da[<C-r>"](<C-r>0)
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""""""""" Links """""""""""""""""""""""""""""""""" {{{
" Open the URL under cursor. Or the last link on the line
" Links are of the form [title](URL)
" TODO wtf is up with \_S and \_s both not working?? This is fucking retarded.
function! notes#openLink()
  " Try to find link under cursor
  echo "nice"
  let l:link_regex = '\[\_[^]]*](\([^)]*\))'
  let l:link = substitute(expand('<cWORD>'), l:link_regex, '\1', '')
  echom l:link
  echom expand('<cWORD>')
  echom getline('.')

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
  %substitute/â¢/*/e
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}

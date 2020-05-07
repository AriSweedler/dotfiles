""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Notes plugin to help me take notes
echom "NOTES PLUGIN FILE SOURCED. THIS SHOULD NOT HAPPEN, ONLY AUTOLOAD!"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" {{{
""""""""""""""""""""""""""""" Initialize notes """"""""""""""""""""""""""""" {{{
function! notes#init()
  "echom "NOTES INIT AUTOLOAD FUNCTION SOURCED!"

  " This allows links to be displayed prettier
  setlocal nowrap
  setlocal conceallevel=2
  setlocal concealcursor=nc

  " Use gx to open the first link on this line.
  " Use <Leader>gx to open the link in the parenthesis you're hovering over.
  nnoremap gx :!open <C-r>=notes#GetLink(getline('.'))<CR>
  nnoremap <Leader>gx "0yi(:!open "<C-r>0"<CR>

  command! UpdateDates global/(in \d* days) !/normal dgn$h\1A !<C-_>

  let g:notes#prev_cur_pos = {}

  " Remap <bang> to mark or toggle DO/DONE
  nnoremap ! :call notes#Banglist_controller('sub', 'DO', 'DONE')<CR>
  nnoremap <Leader>! :call notes#Banglist_controller('find', 'DO', '')<CR>
  nnoremap ? :call notes#Banglist_controller('sub', 'DO', 'Backburner')<CR>

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
  command! FixMe keeppatterns call notes#FixPastedFunction()
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""""""""" Links """""""""""""""""""""""""""""""""" {{{
" Mapping + function to open the URL from a link in the current line.
" Links are of the form [title](URL)
function! notes#GetLink(mdLink)
  let link = substitute(a:mdLink, '^.*\[.*\](\(.*\)).*$', '"\1"', '')
  return link
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""""""" TODOlist """"""""""""""""""""""""""""""""" {{{

" Helper function to check if the cursor has moved since the last invocation
" of this function.
function! notes#CursorUnmoved(tag)
  let prev = exists("g:notes#prev_cur_pos[a:tag]") ? g:notes#prev_cur_pos[a:tag] : [0]
  let answer = (l:prev == getpos('.'))

  " Update tag's prev_cur_pos and return the answer
  let g:notes#prev_cur_pos[a:tag] = getpos('.')
  return answer
endfunction

" There are a few things the "Banglist" function can do, depending on how it's
" invoked. Here they were, in order of priority:
" 1) If invoked with a flag, do the specified behavior.
" 2) If the cursor is moved in between invocations, change the next DO to DONE
" 3) If the cursor is unmoved, repeat the previous behavior's sequence (stored
"    in variable s:banglist_mode)
function! notes#Banglist_controller(mode, src, dst)
  let l:unmoved = notes#CursorUnmoved("notes#Banglist")
  let l:mode = (l:unmoved && a:mode == 'sub') ? 'slide' : a:mode
  let l:banglist_args = {'mode': l:mode, 'src': a:src, 'dst': a:dst}

  echo l:banglist_args
  call notes#banglist#main(l:banglist_args)

  " Invoke CursorUnmoved so a repeat invocation will think the cursor is unmoved
  normal! zx
  call notes#CursorUnmoved("notes#Banglist")
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
function! notes#FixPastedFunction()
  %substitute/â/-/e
  %substitute/â/'/e
  %substitute/â/"/e
  %substitute/â/"/e
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}

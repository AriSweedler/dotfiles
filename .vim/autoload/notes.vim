""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Notes plugin to help me take notes
echom "NOTES PLUGIN FILE SOURCED. THIS SHOULD NOT HAPPEN, ONLY AUTOLOAD!"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""{{{

"""""""""""""""""""""""""""""" Initialize notes """""""""""""""""""""""""""""""{{{
function! notes#init()
  echom "NOTES INIT AUTOLOAD FUNCTION SOURCED!"

  " This allows links to be displayed prettier
  setlocal nowrap
  setlocal conceallevel=2
  setlocal concealcursor=nc

  " Use gx to open the first link on this line.
  " Use <Leader>gx to open the link in the parenthesis you're hovering over.
  nnoremap gx :!open <C-r>=notes#GetLink(getline('.'))<CR>
  nnoremap <Leader>gx "0yi(:!open "<C-r>0"<CR>

  command! UpdateDates global/(in \d* days) !/normal dgn$h\1A !<C-_>

  " Classes will take a paragraph starting with "# ## Classes ####" in the other
  " window and bring it over to this window. Then it'll remove all lines with
  " the word "DONE" in them. Then it'll update the due dates.
  "
  " TODO is there a better way to do this?
  nnoremap <Plug>nice <C-w><C-w>/# ## Classes ####<CR>V}y<C-w><C-w>o<C-c>gpdd:global/DONE/d<CR>:UpdateDates<CR>
  command! Classes .normal <Plug>nice

  let g:notes#prev_cur_pos = {}

  " Remap <bang> to invoke the proper helper function
  nnoremap ! :call notes#MarkDone()<CR>

  "command -nargs=? Yesterday call notes#Yesterday_Helper("tabedit", <args>)

endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}

"""""""""""""""""""""""""""""""""""" Links
""""""""""""""""""""""""""""""""""""{{{
" Mapping + function to open the URL from a link in the current line.
" Links are of the form [title](URL)
function! notes#GetLink(mdLink)
  let link = substitute(a:mdLink, '^.*\[.*\](\(.*\)).*$', '"\1"', '')
  return link
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}

"""""""""""""""""""""""""""""""""" TODOlist
"""""""""""""""""""""""""""""""""""{{{
" TODO rehaul this bull.
" Desired features:
" " Bring the TODOlist over from Yesterday
" " When doing this, delete DONEs
" " Easy to mark something as DONE


" Helper function to check if the cursor has moved since the last invocation
" of this function.
function! notes#CursorUnmoved(tag)
  let prev = exists("g:notes#prev_cur_pos[a:tag]") ? g:notes#prev_cur_pos[a:tag] : [0]
  let answer = (l:prev == getpos('.'))

  " Update tag's prev_cur_pos and return the answer
  let g:notes#prev_cur_pos[a:tag] = getpos('.')
  return answer
endfunction

" Change the next DO to a DONE.
"
" If invoked right after a previous invocation without moving, then undo the
" previous change from DO to DONE, and change the *next* DO to DONE. (You can
" cycle through all your DOs in this fashion, wrapping around once you get to
" the bottom)
function! notes#MarkDone()
  let pattern_start = '\* \<\zs'
  let pattern_DO = 'DO'
  let pattern_DONE = 'DONE'
  let pattern_end = '\ze\>.*!'

  " If we are unmoved, DONE-->DO, move cursor down a line.
  if notes#CursorUnmoved("DO_DONE")
    echom "Cursor unmoved. UNDONE this DONE into a DO and move on"
    let @/ = pattern_start . pattern_DONE . pattern_end
    .normal ncgnDOj
  endif

  let @/ = pattern_start . pattern_DO . pattern_end
  .normal ncgnDONE

  " Invoke CursorUnmoved so a repeat invocation will think the cursor is unmoved
  call notes#CursorUnmoved("DO_DONE")
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}

"""""""""""""""""""""""""""""""""" Yesterday
""""""""""""""""""""""""""""""""""{{{
" Open up Yesterday's notes file. Take the n'th line from the end in our
" .daykeeper file and open that up
function! notes#Yesterday_Helper(open_method, ...)
  " Get the 1st optional argument (default to 2 if no value provided)
  let days_ago = get(a:, 1, 2)

  " Get the line number in the daykeeper file
  let daykeeper_line = expand("%:.:r")->substitute("/", "\\\\/", "")
  echom "Looking for the daykeeper line " . l:daykeeper_line
  let command = 'sed -n "/' . l:daykeeper_line . '/=" .daykeeper'
  echom "Executing shell command " . l:command
  let absoltue_day = system(l:command)
  let desired_day = l:absoltue_day - l:days_ago
  echom printf("We wanna get from %s, which is absolute=%d. At %d days ago, we wanna get %d", expand("%:.:r"), l:absoltue_day, l:days_ago, l:desired_day)
  if l:desired_day <= 0
    echom "Desired day is not positive. Opening first day."
    let l:desired_day = 1
  endif

  " Create a command to get the file from <days_ago> days ago (must strip
  " trailing newline)
  let command = "head -" . l:desired_day. " .daykeeper | tail -1 | tr -d '\n'"
  let file = system(l:command) . ".md"

  " open up the file
  execute a:open_method . " " . l:file
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""}}}

" Ideally this would all be the "OPERATOR" key - depending on context it'll do
" " One of the following.
" TODO make a helper function to toggle DONE
" TODO make a helper function to execute "edit (g:Yesterday-1)"
" TODO make a helper function that'll bring me to the next TODO
"
" }}}

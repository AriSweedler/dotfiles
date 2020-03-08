runtime after/ftplugin/text.vim

" Set folding for 3-backtick markdown divider block
set foldmethod=marker foldmarker=```block,```
iabbrev codeblock ```block<CR>```<C-c>kA
inoremap { {}<Left>

" TODO is there a better way to do this? I'd love to just `!open
" expand('<cURL>')`, or something like that

" Mapping + function to open the URL from a link in the current line.
" Links are of the form [title](URL)
function! s:GetLink(mdLink)
  let link = substitute(a:mdLink, '^.*\[.*\](\(.*\)).*$', '"\1"', '')
  return link
endfunction
nnoremap gx :!open <C-r>=<SID>GetLink(getline('.'))<CR>
nnoremap <Leader>gx "0yi(:!open "<C-r>0"<CR>

setlocal nowrap
setlocal conceallevel=2
setlocal concealcursor=nc

command! UpdateDates global/(in \d* days) !/normal dgn$h\1A !<C-_>

" TODO is there a better way to do this?
nnoremap <Plug>nice <C-w><C-w>/# ## Classes ####<CR>V}y<C-w><C-w>o<C-c>gpdd:global/DONE/d<CR>:UpdateDates<CR>
command! Classes .normal <Plug>nice

" TODO hoist out a ~TODOlist~ plugin
" Helper function to check if the cursor has moved since the last invocation of
" this function.
" TODO add a tag to it? The tag can reference into a dictionary object that is
" prev_cursor_pos_tagged or something. That way we can keep track of all sorts
" of different boys Cursors
function! s:CursorUnmoved()
  let answer = exists("b:prev_cursor_pos") && b:prev_cursor_pos == getpos('.')
  let b:prev_cursor_pos = getpos('.')
  return answer
endfunction

" Change the next DO to a DONE.
"
" If invoked right after a previous invocation without moving, then undo the
" previous change from DO to DONE, and change the *next* DO to DONE. (You can
" cycle through all your DOs in this fashion, wrapping around once you get to
" the bottom)
function! s:MarkDone()
  let pattern_start = '\* \<\zs'
  let pattern_DO = 'DO'
  let pattern_DONE = 'DONE'
  let pattern_end = '\ze\>.*!'

  "  If we are unmoved, DONE-->DO, move cursor down a line.
  if s:CursorUnmoved()
    echom "Cursor unmoved. UNDONE this DONE into a DO and move on"
    let @/ = pattern_start . pattern_DONE . pattern_end
    .normal ncgnDOj
  endif

  let @/ = pattern_start . pattern_DO . pattern_end
  .normal ncgnDONE

  " Invoke CursorUnmoved so a repeat invocation will think the cursor is unmoved
  call s:CursorUnmoved()
endfunction
nnoremap ! :call <SID>MarkDone()<CR>

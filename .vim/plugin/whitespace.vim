nnoremap <silent> <Leader>w :let @/ = '\s$'<CR>:setlocal list!<CR>
nnoremap <silent> <Leader>W :call lib#remove_trailing_whitespace('%')<CR>
nnoremap <silent> <Leader>tw :<C-u>call lib#change_text_width(v:count)<CR>

""""""""""""""""""" Get fancy listchars if it’s supported """""""""""""""""" {{{
if (&termencoding ==# 'utf-8' || &encoding ==# 'utf-8') && version >= 700
  set listchars=tab:\¦›,space:⋅,eol:¬,nbsp:+,
  set fillchars=vert:\|,fold:\⋅,
  "set showbreak=↪.
  set showbreak=☞\ " "Leave this comment and extra whitespace
else
  set listchars=tab:X-,space:.,eol:$,nbsp:+,
  set fillchars=vert:\|,fold:\~
  set showbreak=->
endif
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}

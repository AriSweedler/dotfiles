" https://www.reddit.com/r/vim/comments/frlzt8/create_your_own_text_object/
function! s:make_o_from_v(keys)
  execute printf("onoremap <silent> %s :<C-u>normal v%s<CR>", a:keys, a:keys)
endfunction

" Define a text object for the whole buffer
"xnoremap <silent> wb GoggV

" Easily define a text object for C-style commends
xnoremap <silent> a* [*o]*
call <SID>make_o_from_v("a*")

" Define a text object for editing regexes (single line, inside of //s)
xnoremap <silent> i/ F/lof/h
call <SID>make_o_from_v("i/")

" Define a text object for "arg"s
" foo(a, b, c, d)
" foo(a, *b*, c, d) - in arg
" foo(a, *b, *c, d) - around arg
xnoremap <silent> ia F,llof,h
xnoremap <silent> aa F,lloWh
call <SID>make_o_from_v("ia")
call <SID>make_o_from_v("aa")

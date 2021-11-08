function! s:surround_map(invoker, left, right)
  " Visual mode mapping: `s<invoker>` will surround the visual text with
  " <a:left><a:right>
  execute printf('vnoremap s%s c%s<C-r>"%s<C-c>', a:invoker, a:left, a:right)
  " Normal mode mapping: `<C-s><invoker>` will viws<invoker>
  execute printf('nmap <C-s>%s viws%s', a:invoker, a:invoker)
  " Normal mode mapping: `<Leader><invoker>` will remove the difference between
  " the text object `i<invoker>` and `a<invoker>`.
  execute printf('nnoremap <Leader>%s "0di%s"_da%s"0Pa <Esc>', a:invoker, a:invoker, a:invoker)
endfunction

" Adding and removing works for these
call s:surround_map('`', '`', '`')
call s:surround_map('"', '"', '"')
call s:surround_map("'", "'", "'")
call s:surround_map('(', '(', ')')
call s:surround_map('{', '{', '}')
call s:surround_map('[', '[', ']')
call s:surround_map('<', '<', '>')

" TODO Don't yet have the word objects for these to remove them - as it relies
" on `da*` which doesn't exist. Need to write `a*` if we want this to work.
call s:surround_map("*", "*", "*")
call s:surround_map("_", "_", "_")

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Create a function that tells me how many days it is until a date (of the
" form 'month/day').
"
" This is useful to me when I'm writing to-do lists, and I want to know how
" many days I have to complete a task.
"
" TODO You can actually attack by performing a python injection if l:input
" starts with ' and stuff, but whatever (for now)
"
" TODO this is fragile. I shouldn't have '2020' hardcoded (well... I probably
" won't use this in a year, but whatever)
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function s:Due()
  " Shoutout to Matt https://vi.stackexchange.com/a/22702/14861
  let input = expand('<cWORD>')

  " Parse dates of the form 'month/day'
  let python_command = "from datetime import date; (mm, dd) = '" . l:input . "'.split('/'); print (date(2020,int(mm),int(dd))-date.today()).days"
  let shell_command = printf('python -c "%s"', l:python_command)
  let shell_output = system(l:shell_command)

  " Write the output of the shell command into the buffer
  " ('normal kJ' ==> at the end of the current line instead of on a new line)
  let answer = printf("(in %d days)", l:shell_output)
  put=l:answer
  normal kJb
endfunction

""""""""""""""""""""""""" Mappings to invoke function """"""""""""""""""""""""
" Add a date
nnoremap <Leader>1 :call <SID>Due()<CR>
" Replace a date
nnoremap <Leader>2 f(da(x:call <SID>Due()<CR>

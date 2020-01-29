" TODO You can actually attack by performing a python injection if l:input
" starts with ' and stuff, but whatever (for now)

function s:Due()
  normal "0yiW
  let input = @0

  " Parse dates of the form 'month/day'
  let python_command = "from datetime import date; (mm, dd) = '" . l:input . "'.split('/'); print (date(2020,int(mm),int(dd))-date.today()).days"
  let shell_command = printf('python -c "%s"', l:python_command)
  let shell_output = system(l:shell_command)

  " Write the output of the shell command into the buffer
  " ('normal kJ' ==> at the end of the current line instead of on a new line)
  put=printf("(in %d days)", l:shell_output)
  normal kJ
endfunction

nnoremap <Leader>1 :call <SID>Due()<CR>

function! InsertTmuxNewlines()
  " 275 should really be a range. It should be ~= $COLUMNS. Minus like 5 or 6
  " or so idk.
  let pattern='\s\+'.'\(\%274v\|\%275v\|\%276v\|\%277v\|\)'.'\d\+\s\{5}'
  execute 'substitute/'.pattern."/\n/g"
endfunction
command TMUX call InsertTmuxNewlines()

" Change whitespace that matches it into a newline

" Enable focus event tracking, see  :help xterm-focus-event
let &t_fe = "\<Esc>[?1004h"
let &t_fd = "\<Esc>[?1004l"
execute "set <FocusGained>=\<Esc>[I"
execute "set <FocusLost>=\<Esc>[O"

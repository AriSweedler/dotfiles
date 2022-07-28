"""""""""""""""""""""""""""""""""" watcher.vim """""""""""""""""""""""""""""""""
"
" * Specify a command (in a vim window)
"   * Make a change and watch it get re-executed and displayed
" * command to invoke (& how is the command used - commandline args, stdin) is
"   configurable (in another vim window)
" * automatically watch it get executed by seeing the output in a 3rd (editable)
"   vim window
"   * When you're in this 3rd window the command doesn't refresh when you make
"   changes
"
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

command BrettVictorInit call s:init()
let s:bufname_in = "brett_victor_input"
let s:bnr_in = -1
let s:bufname_out = "brett_victor_output"
let s:bnr_out = -1
function! s:init()
  " Set up the input buffer
  let s:bnr_in = s:bufname_in->bufadd()
  call bufload(s:bnr_in)
  call setbufline(s:bnr_in, 1, ['Place commands here - they will be executed as a shell command'])
  call setbufvar(s:bnr_in, '&buflisted', 1)
  call setbufvar(s:bnr_in, '&buftype', "nofile")

  " Open the input buffer in a window. Set autocmds on it
  execute "vertical split ".s:bufname_in
  augroup BrettVictor
      autocmd!
      autocmd InsertLeave <buffer> call s:update_brett_out()
  augroup END

  " Set up the output buffer
  let s:bnr_out = s:bufname_out->bufadd()
  call bufload(s:bnr_out)
  call setbufvar(s:bnr_out, '&buflisted', 1)
  call setbufvar(s:bnr_out, '&buftype', "nofile")

  " Open the output buffer in a window
  execute "split ".s:bufname_out

  " Go to the input buffer
  execute s:bnr_in->bufwinnr()."wincmd w"
endfunction

function! s:update_brett_out()
  " Invoke command from 'brett_in' buffer
  let l:cmd = s:bnr_in->getbufline(1, "$")[0]
  let l:output_arr = l:cmd->systemlist()

  " Exit early if failed
  if v:shell_error
    echom 'Shell command failed'
    return
  endif

  echom "Using command '".l:cmd."' and getting the output '".l:output_arr[0]."' - we edit".s:bnr_out." to contain that"
  call deletebufline(s:bnr_out, 1, "$")
  call setbufline(s:bnr_out, 1, l:output_arr)
endfunction

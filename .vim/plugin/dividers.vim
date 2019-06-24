"TODO figure out how to load and unload plugins ?
"TODO support multiline comments ?


" TODO maybe read from '&comments' (see :help format-comments) instead of
" needing to use --filetype %s

"""""""""""""""""""""""""""""""" Include guard """""""""""""""""""""""""""""""
if exists("g:loaded_dividers")
  finish
endif
let g:loaded_dividers = 1
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

"""""""""""""""""""""""""""""""" Function body """""""""""""""""""""""""""""""
function s:GetArgs(width, ...)
  let l:width = a:width ? a:width : (&textwidth ? &textwidth : 80)
  let l:text = a:0 > 0 ? a:1 : ""
  return printf("--filetype %s --width %s %s", &filetype, l:width, l:text)
endfunction

function s:Textless(width)
  execute "read !divider " . s:GetArgs(a:width)
endfunction

function s:Yanked(width)
  let l:text = shellescape(@", 1)
  execute "read !divider " . s:GetArgs(a:width, l:text)
endfunction
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Expose a globally scoped name that can hook into the script-scoped functions
noremap <unique> <script> <Plug>DividersCurrentline 0y$:call <SID>Yanked(v:count)<CR>kdd
noremap <unique> <script> <Plug>DividersTextless :call <SID>Textless(v:count)<CR>
noremap <unique> <script> <Plug>DividersYanked :call <SID>Yanked(v:count)<CR>
noremap <unique> <script> <Plug>DividersVisual y:call <SID>Yanked(v:count)<CR>
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

"""""""""""" DEFAULT MAPPINGS: Map keystrokes to the global names. """""""""""
"""""""" Only use these mappings if the users haven't defined anything """""""
if !hasmapto('<Plug>DividersCurrentline')
  nmap <unique> <Leader>d <Plug>DividersCurrentline
endif
if !hasmapto('<Plug>DividersTextless')
  map <unique> <Leader>DD <Plug>DividersTextless
endif
if !hasmapto('<Plug>DividersYanked')
  nmap <unique> <Leader>Dd <Plug>DividersYanked
endif
if !hasmapto('<Plug>DividersVisual')
  vmap <unique> <Leader>d <Plug>DividersVisual
endif
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

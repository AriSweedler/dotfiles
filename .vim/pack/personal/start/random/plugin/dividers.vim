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
" Also, save v:count in a local variable before overwriting it with '0y$' or
" 'y' or something. Then call the functions with the proper value.

"TODO write a getter/setter function instead of putting this in the global
"namespace
"TODO Use autoload functionality
"(https://vi.stackexchange.com/questions/14008/how-an-autoload-file-vim-is-loaded)
"(http://learnvimscriptthehardway.stevelosh.com/chapters/53.html)
"(https://superuser.com/questions/566721/vim-script-is-it-possible-to-refer-to-script-local-variables-in-mappings)
let g:dividers_count = 0
noremap <unique> <script> <Plug>DividersCurrentline :<C-u>let g:dividers_count=v:count<CR>0y$:call <SID>Yanked(g:dividers_count)<CR>kdd
noremap <unique> <script> <Plug>DividersTextless :<C-u>let g:dividers_count=v:count<CR>:call <SID>Textless(g:dividers_count)<CR>
noremap <unique> <script> <Plug>DividersYanked :<C-u>let g:dividers_count=v:count<CR>:call <SID>Yanked(g:dividers_count)<CR>
noremap <unique> <script> <Plug>DividersVisual :<C-u>let g:dividers_count=v:count<CR>y:call <SID>Yanked(g:dividers_count)<CR>
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

"""""""""""" DEFAULT MAPPINGS: Map keystrokes to the global names. """""""""""
"""""""" Only use these mappings if the users haven't defined anything """""""
if !hasmapto('<Plug>DividersCurrentline')
  nmap <unique> <Leader>d <Plug>DividersCurrentline
endif
if !hasmapto('<Plug>DividersTextless')
  map <unique> <Leader>D <Plug>DividersTextless
endif
if !hasmapto('<Plug>DividersYanked')
  nmap <unique> <Leader><Leader>d <Plug>DividersYanked
endif
if !hasmapto('<Plug>DividersVisual')
  vmap <unique> <Leader>d <Plug>DividersVisual
endif
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

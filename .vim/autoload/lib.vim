""""""""""""""""""""""""""""""" Include guard """""""""""""""""""""""""""""" {{{
if exists('g:autoloaded_sweedler_lib')
  finish
endif
let g:autoloaded_sweedler_lib = 1
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""""" Cursor moved helper """"""""""""""""""""""""""" {{{
" Helper function to check if the cursor has moved since the last invocation
" of this function.
let g:lib#prev_cur_pos = {}
function! lib#cursorUnmoved(tag)
  let prev = exists("g:lib#prev_cur_pos[a:tag]") ? g:lib#prev_cur_pos[a:tag] : [0]
  let answer = (l:prev == getpos('.'))

  " Update tag's prev_cur_pos and return the answer
  let g:lib#prev_cur_pos[a:tag] = getpos('.')
  return answer
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""" Toggle syntax on or off """"""""""""""""""""""""" {{{
function! lib#toggleSyntax()
  let &syntax=(&syntax == "OFF") ? &filetype : "OFF"
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""" Left column info toggler """"""""""""""""""""""""" {{{
let g:lib#showLeftColumns = 1
function! lib#toggleLeftColumns()
  if g:lib#showLeftColumns
    " Turn all the gutter info OFF
    let g:lib#showLeftColumns = 0
    GitGutterDisable
    setlocal nonumber norelativenumber
    setlocal signcolumn=no
    setlocal foldcolumn=0
  else
    " Turn all the gutter info ON
    let g:lib#showLeftColumns = 1
    GitGutterEnable
    setlocal number relativenumber
    setlocal signcolumn=yes
    setlocal foldcolumn=2
  endif
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""""" dotfiles and gitgutter """""""""""""""""""""""""" {{{
let s:df_git = "git --git-dir=$HOME/dotfiles/ --work-tree=$HOME"
" Cache answer per buffer. Figure this out by listing all the dotfiles and
" checking if the current filname is in it.
function! lib#in_dotfiles()
  if exists('b:in_dotfiles')
    return b:in_dotfiles
  endif

  " Get the current file's name relative to `~`, but without the leading `~/`.
  "
  " This is the desired format because `git ls-tree --name-only` does this and
  " I just wanna match what they do so I can grep later.
  "
  " See `:help %:~`. And then I chained it with `:s|<pat>|<sub>|`. Regex looks
  " really confusing when magic characters need to be treated as literals, but
  " there's nothing more expressive.
  let filename = expand('%:~:s|\~/||')

  " See if this file's name is in the dotfiles git tree
  call system(s:df_git . " ls-tree --full-tree -r --name-only HEAD | grep ^" . l:filename)

  " If grep found a match, then it will return 0. So we set 'in dotfiles' to 1.
  let b:in_dotfiles = (! v:shell_error)

  return lib#in_dotfiles()
endfunction
function! lib#update_gitgutter_dotfile() abort " {{{
  let g:gitgutter_git_executable = lib#in_dotfiles() ? s:df_git : "git"
endfunction " }}}
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""" For copy/pasting from PDFs """""""""""""""""""""""" {{{
" Change curly quotes into regular quotes and stuff
command! FixPastedPDF keeppatterns call lib#fixPastedPDF()

" For copy/pasting that BS.
function! lib#fixPastedPDF()
  %substitute/â/-/e
  %substitute/â/'/e
  %substitute/â/"/e
  %substitute/â/"/e
  %substitute/â¦/.../e
  %substitute/â¢/*/e
  %substitute/ï /->/e
  %substitute//'/e
  %substitute/’/'/e
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""" break undo sequences """"""""""""""""""""""""""" {{{
function! lib#break_undo()
  execute "normal a\<C-g>u"
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""""""""""""""""" Make a fold """""""""""""""""""""""""""""" {{{
function! lib#new_fold()
  if &foldmethod != "marker"
    echom "Foldmethod not set to marker"
    return
  endif

  if !exists("&foldmarker")
    echom "Foldmarker not set"
    return
  endif

  let my_foldmarkers = split(&foldmarker, ",")
  put =l:my_foldmarkers[0]
  put =l:my_foldmarkers[1]
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
"""""""""""""""""""""""" remove trailing whitespace """""""""""""""""""""""" {{{
" https://vi.stackexchange.com/questions/454/
function! lib#remove_trailing_whitespace(range)
  let save_pos = getpos(".")
  let trailing = '\s\+$'
  execute 'keeppatterns ' . a:range . 'substitute/' . l:trailing . '//e'
  call setpos('.', save_pos)
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}
""""""""""""""""" Use colorcolumn to display the textwidth """"""""""""""""" {{{
" Update textwidth and ColorColumn at the same time
function! lib#change_text_width(...)
  " If we have a v:count, then set the textwidth.
  if a:0 == 1
    let l:width = a:1
    let &textwidth = (l:width)
  endif

  " match the colorcolumn to the textwidth
  let &colorcolumn = (&textwidth)
endfunction
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}

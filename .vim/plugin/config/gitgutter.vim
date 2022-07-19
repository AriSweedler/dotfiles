"""""""""""""""""""""""""""""""""" colors """""""""""""""""""""""""""""""""" {{{
" Tell vim-gitgutter to leave the color of my signcolumn alone
let g:gitgutter_override_sign_column_highlight = 0

" White sign, green background
highlight clear GitGutterAdd
highlight link GitGutterAdd DiffAdd
let g:gitgutter_sign_added = '>+'

" White sign, yellow background
highlight clear GitGutterChange
highlight link GitGutterChange DiffChange
let g:gitgutter_sign_modified = '>~'
let g:gitgutter_sign_modified_removed = '~_'

" Solid red box
highlight clear GitGutterDelete
highlight link GitGutterDelete DiffDelete
let g:gitgutter_sign_removed_first_line = '>‾'
let g:gitgutter_sign_removed = '>_'

highlight clear GitGutterText
highlight link GitGutterText DiffText
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""" shortcuts and settings """"""""""""""""""""""""""" {{{
" Close preview window ( <Leader>hp ) with <Esc>
let g:gitgutter_close_preview_on_escape = 1

" Refresh signs for the current buffer upon write (in case we `git add`ed
" outside of vim and do not have the 'GainedFocus' event)
autocmd BufWritePost * GitGutter

" Put hunks into the location list
" Populate the location list instead of the quickfix list with GitGutterQuickfixList
let g:gitgutter_use_location_list = 1
nnoremap <Leader>GL :GitGutterQuickFix<CR>:lopen<CR>
nnoremap <Leader>Gl :GitGutterQuickFixCurrentFile<CR>:lopen<CR>

" Toggle: Fold all unchanged lines
nnoremap <Leader>Gzx :GitGutterFold<CR>
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""" }}}

" TODO enter 'PATCH' mode. It asks you what to do with each hunk (starting
" from the beginning of the file). 1 keypress to stage, skip, undo.

" TODO GITGUTTER FOCUS
let g:gitgutter_terminal_reports_focus = 0

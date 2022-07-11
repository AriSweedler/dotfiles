"""""""""""""""""""""""""""""""""" colors """""""""""""""""""""""""""""""""" {{{
" Tell vim-gitgutter to leave the color of my signcolumn alone
let g:gitgutter_override_sign_column_highlight = 0

" White sign, green background
highlight GitGutterAdd term=bold ctermfg=188 ctermbg=22
let g:gitgutter_sign_added = '>+'

" White sign, yellow background
highlight GitGutterChange term=bold ctermfg=188 ctermbg=3
let g:gitgutter_sign_modified = '>~'
let g:gitgutter_sign_modified_removed = '~_'

" Solid red box
highlight GitGutterDelete term=bold ctermfg=188 ctermbg=1
let g:gitgutter_sign_removed_first_line = '>‾'
let g:gitgutter_sign_removed = '>_'
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

" TODO GITGUTTER FOCUS
let g:gitgutter_terminal_reports_focus = 0

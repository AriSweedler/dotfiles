setlocal tabstop=2 softtabstop=2 shiftwidth=2 expandtab
setlocal spell autoindent
setlocal foldmethod=syntax
call ChangeTextWidth(80)

" Use vim's "comment" feature to help with making bulleted lists
setlocal comments="bf:*"

" Regex to match 2+ non-whitespace characters if they're surrounded by
" non-whitespace characters.
" let s:MultiSpaceRegex = "\S\zs\( \)\{2,}\ze\S"

" Define a highlight color and apply it to the MultiSpaceRegex
highlight DoubleSpace ctermbg=6
match DoubleSpace /\S\zs\( \)\{2,}\ze\S/

" Store a command in register 'f' to change the next match (of the last used
" search pattern) to " a single space
let @f = "cgn \<C-c>"

" Use the remapping '<leader>f' to place the MultiSpaceRegex in the search
" register, then repeatedly invoke the '@f' macro until it fails.
nnoremap <silent> <leader>f /\S\zs\( \)\{2,}\ze\S<CR>999@f

" TODO upgrade the thing to not clobber the search register by having the
" mapping invoke a function instead of a bunch of keypresses.
function RemoveDoubleSpace()
  " TODO Save the search register
  " TODO Do the operation using the MultiSpace regex
  " TODO Restore the search register
endfunction
" nnoremap <silent> <leader>f :call RemoveDoubleSpace()<CR>

" TODO how to stop highlighting when we're no longer editing a text file
let b:undo_ftplugin = "match DoubleSpace /$$/"

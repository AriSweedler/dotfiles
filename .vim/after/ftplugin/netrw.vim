" Set this to hide files in netrw that gitignore ignores. So cool!?
" let g:netrw_list_hide = netrw_gitignore#Hide()

setlocal relativenumber

# More convenient mapping to "close a tree fold"
nmap <buffer> <silent> <nowait> zc <Plug>NetrwTreeSqueeze

" Open up a background tab
nmap <buffer> <nowait> T t:tabmove $<CR>:tabnext #<CR>

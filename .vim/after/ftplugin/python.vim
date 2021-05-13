setlocal tabstop=4 expandtab
setlocal autoindent foldmethod=indent

nnoremap <Leader>= :!python3 -m black %<CR>L

nnoremap <Leader>A /print(f"\zs\[ARI\]<CR>
iabbrev loggy print(f"[ARI]")<C-o>F"

nnoremap <Leader>f 0da"0f(af<C-c>p
nnoremap <Leader>m :!python3 %<CR>
map <C-m> <Leader>m

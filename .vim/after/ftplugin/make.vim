" Make sure you use real tabs in Makefiles
setlocal tabstop=8 softtabstop=8 shiftwidth=8 noexpandtab

" Easily add a debugging line to the makefile
let @d = "yiw/^debug:$\<CR>o\<Tab>@echo '\<C-r>\": $(\<C-r>\")'\<ESC>\<C-o>*"
let @d = "yiwGo\<Tab>@echo '\<C-r>\": $(\<C-r>\")'\<ESC>\<C-o>*"

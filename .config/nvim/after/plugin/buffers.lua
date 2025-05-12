-- Move between buffers with [b and ]b
vim.keymap.set("n", "[b", ":bprev<CR>")
vim.keymap.set("n", "]b", ":bnext<CR>")

-- Break a window to a new tab. I prefer <C-w>! instead of <C-w>T, it's
-- consistent with tmux. And this is one of the few options that I think tmux
-- got better :)
vim.keymap.set("n", "<C-w>!", "<C-w>T")

-- Change tabs
vim.keymap.set("n", "[t", ":tabprev<CR>")
vim.keymap.set("n", "]t", ":tabnext<CR>")

-- Physically move tabs
vim.keymap.set("n", "<Leader>[t", ":tabmove -<CR>")
vim.keymap.set("n", "<Leader>]t", ":tabmove +<CR>")
vim.keymap.set("n", "<Leader>[T", ":tabmove 0<CR>")
vim.keymap.set("n", "<Leader>]T", ":tabmove $<CR>")

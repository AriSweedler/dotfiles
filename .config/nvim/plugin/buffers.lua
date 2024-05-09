-- Move betwen buffers with [b and ]b
vim.keymap.set("n", "[b", ":bprev<Enter>")
vim.keymap.set("n", "]b", ":bnext<Enter>")

-- Close buffers
vim.keymap.set("n", "<Leader>bc", ":bnext <Bar> :bdelete #<Enter>")
vim.keymap.set("n", "<Leader>BC", ":lua vim.api.nvim_buf_delete(0, {})<Enter>")

-- Break a window to a new tab. I prefer <C-w>! instead of <C-w>T, it's
-- consistent with tmux. And this is one of the few options that I think tmux
-- got better :)
vim.keymap.set("n", "<C-w>!", "<C-w>T")

-- Change tabs
vim.keymap.set("n", "[t", ":tabprev<Enter>")
vim.keymap.set("n", "]t", ":tabnext<Enter>")

-- Physically move tabs
vim.keymap.set("n", "<Leader>[t", ":tabmove -<Enter>")
vim.keymap.set("n", "<Leader>]t", ":tabmove +<Enter>")
vim.keymap.set("n", "<Leader>[T", ":tabmove 0<Enter>")
vim.keymap.set("n", "<Leader>]T", ":tabmove $<Enter>")

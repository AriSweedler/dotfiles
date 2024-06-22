-- Move betwen buffers with [b and ]b
vim.keymap.set("n", "[b", function()
	vim.cmd("bprev")
end)
vim.keymap.set("n", "]b", function()
	vim.cmd("bnext")
end)

-- Close buffers
vim.keymap.set("n", "<Leader>bc", function()
	vim.cmd("bnext")
	vim.cmd("bdelete #")
end)
vim.keymap.set("n", "<Leader>BC", function()
	vim.api.nvim_buf_delete(0, {})
end)

-- Break a window to a new tab. I prefer <C-w>! instead of <C-w>T, it's
-- consistent with tmux. And this is one of the few options that I think tmux
-- got better :)
vim.keymap.set("n", "<C-w>!", "<C-w>T")

-- Change tabs
vim.keymap.set("n", "[t", function()
	vim.cmd("tabprev")
end)
vim.keymap.set("n", "]t", function()
	vim.cmd("tabnext")
end)

-- Physically move tabs
vim.keymap.set("n", "<Leader>[t", function()
	vim.cmd("tabmove -")
end)
vim.keymap.set("n", "<Leader>]t", function()
	vim.cmd("tabmove +")
end)
vim.keymap.set("n", "<Leader>[T", function()
	vim.cmd("tabmove 0")
end)
vim.keymap.set("n", "<Leader>]T", function()
	vim.cmd("tabmove $")
end)

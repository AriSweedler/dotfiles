-- Map <C-f> to leave you in normal mode, written
vim.keymap.set("i", "<C-f>", function()
	vim.cmd("stopinsert")
	vim.cmd("write")
end)
vim.keymap.set("n", "<C-f>", function()
	vim.cmd("write")
end)
vim.keymap.set("v", "<C-f>", "<Esc>:w<Enter>")
vim.keymap.set("v", "<C-f>", function()
	vim.cmd("startinsert")
	vim.cmd("stopinsert")
	vim.cmd("write")
end)

-- Map <C-g> to quit
vim.keymap.set("n", "<C-g>", function()
	vim.cmd("q")
end)

-- jk to exit insert
vim.keymap.set("i", "jk", "<Esc>")
vim.keymap.set("i", "Jk", "<Esc>")
vim.keymap.set("i", "JK", "<Esc>")

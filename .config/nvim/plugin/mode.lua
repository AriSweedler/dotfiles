-- Map <C-f> to leave you in normal mode, written
vim.keymap.set("i", "<C-f>", "<Esc>:w<Enter>")
vim.keymap.set("n", "<C-f>", ":w<Enter>")
vim.keymap.set("v", "<C-f>", "<Esc>:w<Enter>")

-- Map <C-g> to quit
vim.keymap.set("n", "<C-g>", ":q<Enter>")

-- jk to exit insert
vim.keymap.set("i", "jk", "<Esc>")

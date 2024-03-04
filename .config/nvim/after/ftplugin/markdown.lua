vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.cmd([[highlight clear Special | highlight link Special Title]])
vim.o.spell = true
vim.o.spelllang = "en_us"

-- TODO what operations do I wanna do?
vim.keymap.set("n", "]z", "]s", { noremap = true, silent = true })

-- Source the folding lib
vim.o.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"

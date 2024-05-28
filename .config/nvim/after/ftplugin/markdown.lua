vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.spell = true
vim.o.spelllang = "en_us"

-- Source the folding lib
vim.o.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"

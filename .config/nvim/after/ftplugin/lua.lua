vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.expandtab = false

require("ari.lsp.lua_ls")

vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"

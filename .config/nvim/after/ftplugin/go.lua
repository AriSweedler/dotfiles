vim.bo.tabstop = 2
vim.bo.shiftwidth = 2
vim.bo.expandtab = false

require("ari.lsp.gopls")

vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"

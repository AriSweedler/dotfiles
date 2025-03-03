vim.bo.tabstop = 2
vim.bo.shiftwidth = 2
vim.bo.expandtab = false

require("ari.lsp.gopls")

vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"

-- Put in the comment leader when hitting '<Enter>' while in insert mode on a comment
vim.opt.formatoptions:append("r")
-- Put in the comment leader when hitting 'O' while in normal mode on a comment
vim.opt.formatoptions:append("o")
-- a	Automatic formatting of paragraphs.  Every time text is inserted or
-- 	deleted the paragraph will be reformatted.  See |auto-format|.
-- 	When the 'c' flag is present this only happens for recognized
-- 	comments.
-- vim.opt.formatoptions:append("a")

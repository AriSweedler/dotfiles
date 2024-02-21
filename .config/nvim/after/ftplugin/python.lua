vim.o.textwidth = 0 -- Unset textwidth

vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"

-- make a mapping for '!' that when it is pressed, we take the logline on the
-- current line (logger.{debug,info,warn,error}) and cycle the severity to be 1
-- higher than it was before. Or we wrap around to the start. Use a function

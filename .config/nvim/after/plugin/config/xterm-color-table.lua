-- I just wanna use X[tT]erm - no need for all these options
vim.cmd("command! Xterm TXtermColorTable")
vim.cmd("command! XTerm TXtermColorTable")
vim.cmd("silent! delcommand XtermColorTable")
vim.cmd("silent! delcommand SXtermColorTable")
vim.cmd("silent! delcommand VXtermColorTable")
vim.cmd("silent! delcommand EXtermColorTable")
vim.cmd("silent! delcommand OXtermColorTable")

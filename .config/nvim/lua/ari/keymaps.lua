-- Diagnostic keymaps
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous diagnostic message" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next diagnostic message" })
vim.keymap.set("n", "<Leader>e", vim.diagnostic.open_float, { desc = "Open floating diagnostic message" })
vim.keymap.set("n", "<Leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostics list" })

-- Star is for highlighting, not for movement
vim.keymap.set("n", "*", "*N")
-- vim.keymap.set("n", "g*", "<Leader>Sw")
-- TODO: I need a keymap to replace 'lgrep'
-- TODO: I need a keymap to move stuff from telescope to loclist

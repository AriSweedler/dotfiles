local builtin = require("telescope.builtin")

vim.keymap.set("n", "<Leader>SLr", builtin.lsp_references, { desc = "[S]earch [L]SP [r]eferences" })
vim.keymap.set("n", "<Leader>SLi", builtin.lsp_incoming_calls, { desc = "[S]earch [L]SP [i]ncoming calls" })
vim.keymap.set("n", "<Leader>SLo", builtin.lsp_outgoing_calls, { desc = "[S]earch [L]SP [o]utgoing calls" })
vim.keymap.set("n", "<Leader>SLI", builtin.lsp_implementations, { desc = "[S]earch [L]SP [I]mplementations" })

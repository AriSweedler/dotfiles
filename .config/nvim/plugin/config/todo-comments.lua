local tc = require("todo-comments")
vim.keymap.set("n", "]]t", tc.jump_next, { desc = "Next todo comment" })
vim.keymap.set("n", "[[t", tc.jump_prev, { desc = "Previous todo comment" })

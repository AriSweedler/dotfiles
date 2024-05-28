local builtin = require("telescope.builtin")

-- I feel like this misses some highlights
vim.keymap.set("n", "<Leader>Sh", builtin.highlights, { desc = "[S]earch [h]ighlights" })

vim.keymap.set("n", "<Leader>Sj", builtin.jumplist, { desc = "[S]earch [j]umplist" })

vim.keymap.set("n", "<Leader>Sa", builtin.autocommands, { desc = "[S]earch [a]utocommands" })

-- Totally unecessary. But fuck it we ball.
-- Removes the native ability to say '1z=' to auto-accept the 1st suggestion.
vim.keymap.set("n", "z=", builtin.spell_suggest)

-- You can stop a telescope search with <C-c>. This will resume it
vim.keymap.set("n", "<Leader>Sr", builtin.resume, { desc = "[S]earch [R]esume" })

-- Find the right file - <C-t> (Except for buffers)
local builtin = require("telescope.builtin")

vim.keymap.set("n", "<C-t>", builtin.git_files, { desc = "Search git files" })
vim.keymap.set("n", "<Leader><C-t>.", builtin.find_files, { desc = "Search pwd files" })
vim.keymap.set("n", "<Leader><C-t>o", builtin.oldfiles, { desc = "Search recently opened files" })

vim.keymap.set("n", "<Leader><C-t>v", function()
	builtin.find_files({
		cwd = vim.fn.stdpath("config"),
	})
end, { desc = "Search vim config files" })

vim.keymap.set("n", "<C-b>", function()
	builtin.buffers({ sort_mru = true })
end, { desc = "Find existing buffers" })

vim.keymap.set("n", "<Leader><C-t>d", function()
	builtin.find_files({
		cwd = "$HOME/",
		prompt_title = "My dotfiles tracked with git",
		find_command = { 'git', 'df', 'ls', '--name-only' },
	})
end, { desc = "Search Git tracked dotfiles" })

vim.keymap.set("n", "<Leader><C-t>S", function()
	require("luasnip.loaders").edit_snippet_files()
end, { desc = "Open from a snippet file" })

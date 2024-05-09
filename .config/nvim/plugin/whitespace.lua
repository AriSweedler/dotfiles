vim.keymap.set("n", "<Leader>w", function()
	vim.bo.list = not vim.bo.list
	-- Prime the next search to find trailing whitespace. Just hit 'n'
	vim.fn.setreg("/", [[\s\+$]])
end, { desc = "Toggle list option" })

vim.keymap.set("n", "<Leader>tw", function()
	print("Setting textwidth to " .. vim.v.count)
	vim.bo.textwidth = vim.v.count
end, { desc = "Set textwidth (accepts v:count)" })

vim.keymap.set("n", "<Leader>W", function()
	vim.cmd([[silent! %s/\s\+$//e]])
end, { desc = "Clear trailing whitespace" })

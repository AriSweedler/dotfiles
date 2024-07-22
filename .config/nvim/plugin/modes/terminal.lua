-- Use escape to exit terminal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>")

-- Or just use <C-w> straight from terminal mode
vim.keymap.set("t", "[t", function()
	vim.api.nvim_input("<C-\\><C-n>")
	vim.cmd("tabprev")
end)
vim.keymap.set("t", "]t", function()
	vim.api.nvim_input("<C-\\><C-n>")
	vim.cmd("tabnext")
end)

-- Make <C-d> in terminal mode send that then <Enter>
vim.keymap.set("t", "<C-g>", function()
	vim.api.nvim_input("<C-\\><C-n>")
	vim.cmd("quit")
end)

-- When we FIRST open the terminal, create an autocommand that triggers every
-- time the buffer gains focus
-- * Every time the buffer gains focus, enter insert mode
vim.api.nvim_create_autocmd("TermOpen", {
	pattern = "term://*",
	callback = function()
		vim.api.nvim_create_autocmd("BufEnter", {
			buffer = 0, -- local autocmd
			callback = function()
				-- Send an 'i' keystroke to enter terminal mode
				vim.api.nvim_feedkeys("i", "n", true)
			end,
		})
	end,
})

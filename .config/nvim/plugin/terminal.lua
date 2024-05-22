-- Use escape to exit terminal mode
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>")

-- Or just use <C-w> straight from terminal mode
vim.keymap.set("t", "[t", "<C-\\><C-n>:tabprev<Enter>")
vim.keymap.set("t", "]t", "<C-\\><C-n>:tabnext<Enter>")
vim.keymap.set("t", "[w", "<C-\\><C-n><C-w>h")
vim.keymap.set("t", "]w", "<C-\\><C-n><C-w>l")

-- Make <C-d> in terminal mode send that then <Enter>
vim.keymap.set("t", "<C-g>", "<C-\\><C-n>:q<Enter>")

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

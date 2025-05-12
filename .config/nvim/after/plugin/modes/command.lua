local augroup = vim.api.nvim_create_augroup("CmdWinCustomizations", { clear = true })

local function bmap(lhs, rhs)
	vim.keymap.set("n", lhs, rhs, {
		noremap = true,
		silent = true,
		buffer = true,
	})
end

vim.api.nvim_create_autocmd("CmdwinEnter", {
	group = augroup,
	pattern = "*",
	callback = function()
		-- print("ARI_MODE_COMMAND: Entering command-line window")

		-- Leaving window abandons commandwindow AND command mode(C-w closes)
		bmap("<C-w>", "<C-c><C-w>")

		-- TODO:
		-- Execute the command, redirect the output to a new split, and keep the
		-- window open
		bmap("<F5>", "<CR>q:")

		-- Set cursorline on for the buffer
		vim.cmd("setlocal cursorline")
	end,
})

vim.api.nvim_create_autocmd("CmdwinLeave", {
	group = augroup,
	pattern = "*",
	callback = function()
		-- print("ARI_MODE_COMMAND: Leaving command-line window")
	end,
})

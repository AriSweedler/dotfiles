return {
	name = "Resize Windows",
	mode = "n",
	invoke_on_body = true,
	body = "<Leader>WW",
	on_enter = function()
		vim.print("Entering hydra " .. "Resize Windows")
	end,
	on_exit = function()
		vim.print("Exiting hydra " .. "Resize Windows")
	end,
	config = {
		color = "pink",
	},
	heads = {
		{ "h", "<C-w><", { desc = "Resize window left" } },
		{ "j", "<C-w>-", { desc = "Resize window down" } },
		{ "k", "<C-w>+", { desc = "Resize window up" } },
		{ "l", "<C-w>>", { desc = "Resize window right" } },
	},
}

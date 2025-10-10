local hydra_config = {
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
		-- pink means:
		-- 1) default key handler does NOT exit the hydra
		-- 2) foreign keys do NOT exit the hydra (need q/<Esc>)
		color = "pink",
	},
	heads = {
		{ "h", "<C-w><", { desc = "Resize window left" } },
		{ "j", "<C-w>-", { desc = "Resize window down" } },
		{ "k", "<C-w>+", { desc = "Resize window up" } },
		{ "l", "<C-w>>", { desc = "Resize window right" } },
	},
}

return hydra_config

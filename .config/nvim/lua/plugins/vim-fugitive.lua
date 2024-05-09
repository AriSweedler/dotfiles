local M = {
	"tpope/vim-fugitive",
	event = "BufReadPre",
	config = function()
		local ari = require("ari")
		ari.map("n", "gb", ":Git blame<Enter>:vertical resize 25<Enter>")
		-- TODO: If we're in dotfiles, then we should use different default args
	end,
}

return M

local M = {
	"echasnovski/mini.nvim",
	event = "BufReadPre",
	config = function()
		require("plugins.mini.config")
	end,
}

return M

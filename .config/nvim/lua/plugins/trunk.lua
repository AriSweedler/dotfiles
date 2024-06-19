local M = {
	"trunk-io/neovim-trunk",
	event = "BufReadPre",
	main = "trunk",
	dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
	opts = {
		logLevel = "trace",
	},
}

return M

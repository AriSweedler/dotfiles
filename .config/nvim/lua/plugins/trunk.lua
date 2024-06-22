local M = {
	"trunk-io/neovim-trunk",
	-- TODO: Disabling for now because it lags my shit
	-- event = "BufReadPre",
	main = "trunk",
	dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
	opts = {
		logLevel = "trace",
	},
}

return M

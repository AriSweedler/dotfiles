local M = {
	"nvim-telescope/telescope.nvim",
	event = "VimEnter",
	branch = "0.1.x",
	dependencies = {
		"nvim-lua/plenary.nvim",
		{
			"nvim-telescope/telescope-fzf-native.nvim",
			build = "make",
			cond = function()
				return vim.fn.executable("make") == 1
			end,
		},
		{ "nvim-telescope/telescope-ui-select.nvim" },
		{ "nvim-tree/nvim-web-devicons" },
	},
	config = function(_, opts)
		require("plugins.telescope.config")
		require("telescope").setup(opts)
	end,
	opts = {
		defaults = {
			mappings = require("plugins.telescope.mappings"),
		},
	},
}

return M

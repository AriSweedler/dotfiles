local M = {
	"nvim-treesitter/nvim-treesitter",
	event = "BufReadPre",
	opts = {},
	dependencies = {
		"nvim-treesitter/nvim-treesitter-textobjects",
	},
	build = ":TSUpdate",
}

return M

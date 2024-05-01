local M = {
	"nvim-lualine/lualine.nvim",
	event = "BufReadPre",
	opts = {
		options = {
			theme = "wombat",
			path = 1,
		},
		sections = {
			lualine_y = { "copilot", "progress" },
		},
	},
	dependencies = {
		"AndreM222/copilot-lualine",
	},
}

return M

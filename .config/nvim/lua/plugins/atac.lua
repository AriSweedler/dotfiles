local M = {
	"NachoNievaG/atac.nvim",
	event = "BufReadPre",
	dependencies = { "akinsho/toggleterm.nvim" },
	config = function()
		require("atac").setup({
			dir = "~/.config/atac",
		})
	end,
}

return M

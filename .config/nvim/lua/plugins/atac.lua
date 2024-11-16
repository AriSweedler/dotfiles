local M = {
	"NachoNievaG/atac.nvim",
	event = "VeryLazy",
	dependencies = { "akinsho/toggleterm.nvim" },
	config = function()
		require("atac").setup({
			dir = "~/.config/atac",
		})
	end,
}

return M

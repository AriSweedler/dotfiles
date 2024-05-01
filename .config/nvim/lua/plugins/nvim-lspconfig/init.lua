local M = {
	"neovim/nvim-lspconfig",
	event = "BufReadPre",
	opts = {},
	dependencies = {
		-- Install LSPs to stdpath for neovim
		"williamboman/mason.nvim",
		"williamboman/mason-lspconfig.nvim",
		"WhoIsSethDaniel/mason-tool-installer.nvim",

		-- Useful status updates for LSP
		{ "j-hui/fidget.nvim", opts = {} },

		-- Additional lua configuration
		"folke/neodev.nvim",
	},
	config = function()
		require("plugins.nvim-lspconfig.config")
	end,
}

return M

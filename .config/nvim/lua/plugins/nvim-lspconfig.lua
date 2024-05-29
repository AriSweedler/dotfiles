local M = {
	"neovim/nvim-lspconfig",
	event = "VeryLazy",
	dependencies = {
		"williamboman/mason.nvim", -- Install LSPs private to nvim
		"WhoIsSethDaniel/mason-tool-installer.nvim", -- Automatically install and update tools via Mason
		"williamboman/mason-lspconfig.nvim", -- Nice default configs for LSPs - saves a lot of work
		{ "j-hui/fidget.nvim", opts = {} }, -- Show long-running LSP commands in statusline
		"folke/neodev.nvim", -- Additional lua configuration (convenience)
		"nvim-telescope/telescope.nvim",
	},
	config = function()
		require("plugins.nvim-lspconfig.config")
	end,
}

return M

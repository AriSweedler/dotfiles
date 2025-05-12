local M = {
	"neovim/nvim-lspconfig",
	event = "VeryLazy",
	dependencies = {
		"williamboman/mason.nvim", -- Install LSPs private to nvim
		"williamboman/mason-lspconfig.nvim", -- Nice default configs for LSPs - saves a lot of work
		{ "j-hui/fidget.nvim", opts = {} }, -- Show long-running LSP commands in statusline
		"nvim-telescope/telescope.nvim",
	},
	config = function()
		-- Ensure the servers and tools above are installed
		local gtn = require("plugins.nvim-lspconfig.get_tool_name").get_tool_names

		require("mason").setup()
		require("mason-lspconfig").setup({ ensure_installed = gtn("ari/lsp") })
	end,
}

return M

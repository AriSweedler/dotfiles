local M = {
	"folke/lazydev.nvim",
	ft = "lua",
	opts = {
		library = {
			-- Load luvit types when the `vim.uv` word is found
			{ path = "luvit-meta/library", words = { "vim%.uv" } },

			-- TODO: Load the LuaSnip types when we're in a "snippet definition file"
			-- https://www.reddit.com/r/neovim/comments/1g2mfbw/how_to_add_luasnipconfigsnip_env_to_language
		},
	},
}

return M

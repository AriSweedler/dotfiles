-- nvim-cmp is not a complete solution. It is more like a shell.
--
-- The plugin expects to be presented with a set of completion engines, each of
-- which comes with config options and includes the all-important completion
-- function that - when invoked - will return a set of available completions.
--
-- nvim-cmp will use the config options to figure out WHEN to call the
-- completion functions (when typing, on a keystroke, etc.) and the results UI
-- (popup menu, results ordering, how to scroll or accept)
--
-- So it should come as no surprise that this plugin has a large set of
-- dependencies - we need to download all these completion engines! (Completion
-- sources), and then we need to configure this plugin to actually USE those
-- engines.
local M = {
	"hrsh7th/nvim-cmp",
	event = "InsertEnter",
	dependencies = {
		-- Make vim's native completions available as sources
		"hrsh7th/cmp-path",
		"hrsh7th/cmp-buffer",

		-- Add LSP as a source (struct fields, variables in scope, etc.)
		"hrsh7th/cmp-nvim-lsp",

		-- 1. Install the LuaSnip snippet engine
		-- 2. Register all the snippets it loads as available from an nvim-cmp source
		{
			"L3MON4D3/LuaSnip",
			build = "make install_jsregexp",
			dependencies = { "saadparwaiz1/cmp_luasnip" },
		},
	},
	config = function()
		require("plugins.nvim-cmp.config")
		require("cmp").register_source("luasnip", require("cmp_luasnip").new())
	end,
}

return M

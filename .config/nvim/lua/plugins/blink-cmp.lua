return {
	{
		"saghen/blink.cmp",
		version = "1.*",
		event = "InsertEnter",
		opts = {
			snippets = {
				expand = function(snippet) require("luasnip").lsp_expand(snippet) end,
			},
			dependencies = {
				"L3MON4D3/LuaSnip",
			},
			completion = {
				documentation = { auto_show = true, auto_show_delay_ms = 200 },
				ghost_text = { enabled = true },
				accept = { auto_brackets = { enabled = true } },
				menu = { draw = { treesitter = { "lsp" } } },
			},
			sources = {
				default = { "lsp", "path", "snippets", "buffer" },
			},
			keymap = {
				preset = "default",
			},
			signature = { enabled = true },
		},
		config = function(_, opts)
			require("blink.cmp").setup(opts)
		end,
	},
}

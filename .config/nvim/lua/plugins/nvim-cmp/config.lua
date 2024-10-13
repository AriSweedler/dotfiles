-- vim.opt.completeopt = { "menu", "menuone", "noselect" }
-- vim.opt.shortmess:append "c"

local cmp = require("cmp")
local sug = require("plugins.nvim-cmp.syntactic_sugar")
require("ari.luasnip")

cmp.setup({
	snippet = sug.ls_expander,
	mapping = {
		-- Start completion
		["<C-Space>"] = cmp.mapping.complete(),
		["<C-s>"] = cmp.mapping.complete(sug.from_sources({ "luasnip" })),

		-- Finish completion
		["<C-y>"] = cmp.mapping(sug.confirm, { "i", "c" }),
		["<Enter>"] = cmp.mapping(sug.confirm, { "i" }),

		-- Movement
		["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
		["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
		["<C-l>"] = cmp.mapping(sug.snip_right, { "i", "s" }),
		["<C-h>"] = cmp.mapping(sug.snip_left, { "i", "s" }),

		-- Less important movements
		["<C-d>"] = cmp.mapping.scroll_docs(-4),
		["<C-f>"] = cmp.mapping.scroll_docs(4),
	},
	-- TODO: should we use (cmp.config.sources)
	sources = {
		-- lazydev has better completions (at least for nvim lua) than the lua
		-- language server's built-in completions. (Language servers ship with
		-- default completions). Let's set group index to 0 to hoist these better
		-- completions above the others
		{ name = "lazydev", group_index = 0, },
		{ name = "luasnip", option = { show_autosnippets = true }, },
		{ name = "nvim_lsp" },
		{ name = "path" },
		{ name = "buffer" },
	},
})

cmp.setup.cmdline("/", {
	mapping = cmp.mapping.preset.cmdline(),
	sources = {
		{ name = "buffer" }
	}
})

cmp.setup.cmdline(":", {
	mapping = cmp.mapping.preset.cmdline(),
	sources = cmp.config.sources({
		{ name = "path" }
	}, {
		{ name = "cmdline" }
	}),
	matching = { disallow_symbol_nonprefix_matching = false }
})

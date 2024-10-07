-- vim.opt.completeopt = { "menu", "menuone", "noselect" }
-- vim.opt.shortmess:append "c"

local cmp = require("cmp")
local luasnip = require("luasnip")

luasnip.config.setup({
	enable_autosnippets = true,
})

local from_source = function(src)
	return {
		config = {
			sources = {
				{ name = src }
			}
		}
	}
end

cmp.setup({
	snippet = {
		expand = function(args)
			luasnip.lsp_expand(args.body)
		end,
	},
	mapping = {
		["<C-Space>"] = cmp.mapping.complete(),
		["<C-s>"] = cmp.mapping.complete(from_source("luasnip")),

		-- TODO: Do '<C-n>' and '<C-p>' work when
		-- 'luasnip.expand_or_locally_jumpable' is possible?
		["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
		["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
		["<C-d>"] = cmp.mapping.scroll_docs(-4),
		["<C-f>"] = cmp.mapping.scroll_docs(4),
		["<C-y>"] = cmp.mapping(
			cmp.mapping.confirm({
				behavior = cmp.ConfirmBehavior.Insert,
				select = true,
			}),
			{ "i", "c" }
		),
	},
	sources = {
		{ name = "luasnip" },
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

-- All loaders (except the vscode-standalone-loader) share a similar interface:
require("luasnip.loaders.from_lua").lazy_load({ paths = { "./snippets" } })

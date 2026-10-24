vim.pack.add({
	"https://github.com/folke/lazydev.nvim",
	"https://github.com/Bilal2453/luvit-meta",
})

---@diagnostic disable-next-line: missing-fields
require("lazydev").setup({
	library = {
		{ path = "luvit-meta/library", words = { "vim%.uv" } },
	},
})

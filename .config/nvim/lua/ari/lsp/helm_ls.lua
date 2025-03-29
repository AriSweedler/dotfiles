local defaults = require("plugins.nvim-lspconfig.defaults")

require("lspconfig").helm_ls.setup({
	on_attach = defaults.on_attach,
	capabilities = require("cmp_nvim_lsp").default_capabilities(),
})

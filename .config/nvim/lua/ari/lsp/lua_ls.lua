local defaults = require("plugins.nvim-lspconfig.defaults")

require('lspconfig').lua_ls.setup {
	on_attach = defaults.on_attach,
	capabilities = require('cmp_nvim_lsp').default_capabilities(),
	settings = {
		Lua = {
			workspace = { checkThirdParty = false },
			telemetry = { enable = false },
		},
	}
}

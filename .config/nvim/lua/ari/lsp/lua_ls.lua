local M = {}

local defaults = require("plugins.nvim-lspconfig.defaults")

M.setup = function()
	require('neodev').setup()
	require('lspconfig').lua_ls.setup {
		on_attach = defaults.on_attach,
		capabilities = defaults.capabilities,
		settings = {
			Lua = {
				workspace = { checkThirdParty = false },
				telemetry = { enable = false },
			},
		}
	}
end

return M

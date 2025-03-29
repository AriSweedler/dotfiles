local defaults = require("plugins.nvim-lspconfig.defaults")

local get_local_module = function()
	-- Find the 'go.mod' file
	local go_mod = vim.fn.findfile("go.mod", ".;")

	-- Use awk to parse the module out of the file
	local module = vim.fn.system("awk '/module / {print $2}' " .. go_mod)
	module = string.gsub(module, "\n", "")

	print("We got the module as: " .. module)
	return module
end

require("lspconfig").gopls.setup({
	on_attach = defaults.on_attach,
	capabilities = require("cmp_nvim_lsp").default_capabilities(),
	settings = {
		gopls = {
			-- Local imports configuration
			["go.imports.local"] = get_local_module(),
		},
	},
})

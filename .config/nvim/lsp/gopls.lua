local get_local_module = function()
	-- Find the 'go.mod' file
	local go_mod = vim.fn.findfile("go.mod", ".;")
	if go_mod == "" then
		vim.notify("No go.mod file found", vim.log.levels.INFO)
		return ""
	end

	-- Use awk to parse the module out of the file
	local module = vim.fn.system("awk '/module / {print $2}' " .. go_mod)
	module = string.gsub(module, "\n", "")
	if module == "" then
		vim.notify("No module found in go.mod", vim.log.levels.WARN)
		return ""
	end

	return module
end

return {
	cmd = { "gopls" },
	filetypes = { "go", "gomod", "gowork", "gotmpl" },
	single_file_support = true,
	root_markers = { 'go.mod' },
	capabilities = require("cmp_nvim_lsp").default_capabilities(),
	settings = {
		gopls = {
			-- Local imports configuration
			["go.imports.local"] = get_local_module(),
			hints = {
				assignVariableTypes = true,
				compositeLiteralFields = true,
				compositeLiteralTypes = true,
				constantValues = true,
				functionTypeParameters = true,
				parameterNames = true,
				rangeVariableTypes = true,
			},
		},
	},
}

local get_root_dir = function(bufnr)
	local fname = vim.api.nvim_buf_get_name(bufnr)
	local root_files = {
		".luarc.json",
		".luarc.jsonc",
		".luacheckrc",
		".stylua.toml",
		"stylua.toml",
		"selene.toml",
		"selene.yml",
		".git",
	}
	for _, root_file in ipairs(root_files) do
		local root_dir = vim.fn.finddir(root_file, vim.fn.fnamemodify(fname, ":p:h") .. ";")
		if root_dir ~= "" then
			return vim.fn.fnamemodify(root_dir, ":h")
		end
	end
	-- If no root file is found, return the current working directory
	return vim.fn.getcwd()
end

return {
	cmd = { "lua-language-server" },
	filetypes = { "lua" },
	root_dir = get_root_dir,
	single_file_support = true,
	log_level = vim.lsp.protocol.MessageType.Warning,
	settings = {
		Lua = {
			workspace = { checkThirdParty = false },
			telemetry = { enable = false },
		},
	},
}

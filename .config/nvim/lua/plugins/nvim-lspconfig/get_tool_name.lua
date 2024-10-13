local M = {}

-- Each tool we require gets a file in this dir.
--
-- But we have to track that ourselves. Contrast with lazy.nvim, where you just say
--
--     require("lazy").setup("plugins", ...
--
-- and we get all these powers and modularity for free. Well - I can just
-- implement this one function and then pretend that we have the same power
M.get_tool_names = function(path_rel_to_config_lua_dir)
	local tool_dir = vim.fn.stdpath("config") .. "/lua/" .. path_rel_to_config_lua_dir
	local tool_files = require("plenary.scandir").scan_dir(tool_dir, { search_pattern = "%.lua$" })
	local tools = {}
	for _, tf in ipairs(tool_files) do
		table.insert(tools, tf:match("([^/]+)%.lua$"))
	end
	print("[nvim-lspconfig/get_tool_names.lua] These are the tools we require: " .. vim.inspect(tools))
	return tools
end

return M

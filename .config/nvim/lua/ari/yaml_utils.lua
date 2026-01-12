local M = {}

-- Get the YAML key path at the cursor position, including array items
-- This extends yaml_nvim.get_yaml_key() to handle array items
function M.get_yaml_key_at_cursor()
	local ans = require("yaml_nvim").get_yaml_key()

	-- If get_yaml_key returns nil, we might be on an array item
	-- Use treesitter directly to get the node and parse it
	if not ans then
		local bufnr = vim.api.nvim_get_current_buf()
		local cursor = vim.api.nvim_win_get_cursor(0)
		local row, col = cursor[1] - 1, cursor[2]

		local parser = vim.treesitter.get_parser(bufnr, "yaml")
		local tree = parser:parse()[1]
		local root = tree:root()

		-- Get the node at cursor position
		local node = root:named_descendant_for_range(row, col, row, col)

		if node then
			-- Use yaml_nvim's pair.parse to get the full path
			local pair = require("yaml_nvim.pair")
			local parsed = pair.parse(node)
			ans = parsed.key
		end
	end

	return ans
end

return M

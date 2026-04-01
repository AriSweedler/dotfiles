local M = {}

--- Walk up from a treesitter node to the root, building the YAML key path.
--- Handles both mapping keys and array items.
--- @param node TSNode
--- @return string
local function build_path(node)
	local parts = {}
	local current = node

	while current do
		local parent = current:parent()
		if not parent then break end

		local parent_type = parent:type()

		if parent_type == "block_mapping_pair" or parent_type == "flow_pair" then
			-- Get the key node (first named child of the pair)
			local key_node = parent:named_child(0)
			if key_node then
				local key = vim.treesitter.get_node_text(key_node, 0)
				table.insert(parts, 1, key)
			end
		elseif parent_type == "block_sequence" or parent_type == "flow_sequence" then
			-- Find the index of current within the sequence
			local idx = 0
			for child in parent:iter_children() do
				if child:named() then
					if child:id() == current:id() then
						table.insert(parts, 1, "[" .. idx .. "]")
						break
					end
					idx = idx + 1
				end
			end
		end

		current = parent
	end

	return table.concat(parts, ".")
end

--- Get the YAML key path at the cursor position, including array items.
--- @return string?
function M.get_yaml_key_at_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local parser = vim.treesitter.get_parser(bufnr, "yaml")
	if not parser then return nil end

	local tree = parser:parse()[1]
	local root = tree:root()

	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	local node = root:named_descendant_for_range(row, col, row, col)

	if not node then return nil end
	return build_path(node)
end

return M

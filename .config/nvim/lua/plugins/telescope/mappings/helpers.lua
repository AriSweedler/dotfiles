local M = {}

--- For each item that's selected, convert it to a QuickfixItem & map 'handler'
--- over the resulting table
--- @param prompt_buffer any The prompt buffer.
--- @param handler fun(item: QuickfixItem): nil A function that handles a quickfix item.
M.handle_selection = function(prompt_buffer, handler)
	-- Send selection to loclist
	local acts = require("telescope.actions")
	acts.smart_send_to_loclist(prompt_buffer)

	-- Get the new location list items
	local selection_as_loclist = vim.fn.getloclist(0)

	-- Print the buffer numbers for debugging
	for _, item in ipairs(selection_as_loclist) do
		handler(item) -- Call the handler for each item
	end

	-- Restore the original loclist (if there WAS one) with 'lolder'.
	-- Swallow the potential error 'no older loclist' with 'pcall'
	pcall(function() vim.cmd("lolder") end)
end

return M

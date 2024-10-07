local function bdelete(item)
	-- If 'bufnr' is not valid or does not exist, return early
	if not item.bufnr or vim.fn.bufexists(item.bufnr) ~= 1 then
		return
	end

	-- Delete the buffer
	vim.cmd("bdelete " .. item.bufnr)
end

local function from_loclist(prompt_buffer, handler)
	-- Smart send to loclist
	local acts = require("telescope.actions")
	acts.smart_send_to_loclist(prompt_buffer)

	-- Get the new location list items
	local new_loclist = vim.fn.getloclist(0)

	-- Print the buffer numbers for debugging
	for _, item in ipairs(new_loclist) do
		print(vim.inspect(item.bufnr))
		handler(item) -- Call the handler for each item
	end

	-- Restore the original loclist (if there WAS one) with 'lolder'.
	-- Swallow the potential error 'no older loclist' with 'pcall'
	pcall(function() vim.cmd("lolder") end)
end

local M = {
	i = {
		["<Esc>"] = "close",
		["<C-h>"] = "which_key",
		["<C-l>"] = function(prompt_buffer)
			local acts = require("telescope.actions")
			acts.smart_send_to_loclist(prompt_buffer)
			acts.open_loclist(prompt_buffer)
		end,
		["<C-b><C-c>"] = function(prompt_buffer)
			from_loclist(prompt_buffer, bdelete)
		end,
		["<Tab>"] = "toggle_selection",
		["<S-Tab>"] = "drop_all",
	},
}

return M

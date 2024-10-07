local ts_helpers = require("plugins.telescope.mappings.helpers")

local function bdelete(item)
	-- If 'bufnr' is not valid or is not open, return early
	if not item.bufnr or vim.fn.bufexists(item.bufnr) ~= 1 then
		return
	end

	-- The buffer is open, close the buffer
	vim.cmd("bdelete " .. item.bufnr)
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
			ts_helpers.handle_selection(prompt_buffer, bdelete)
		end,
		["<Tab>"] = "toggle_selection",
		["<S-Tab>"] = "drop_all",
	},
}

return M

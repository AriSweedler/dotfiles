local acts = require("telescope.actions")

local M = {
	i = {
		["<Esc>"] = "close",
		["<C-h>"] = "which_key",
		["<C-l>"] = function(prompt_buffer)
			acts.smart_send_to_loclist(prompt_buffer)
			acts.open_loclist(prompt_buffer)
		end,
		["<Tab>"] = "toggle_selection",
		["<S-Tab>"] = "drop_all",
	},
}

return M

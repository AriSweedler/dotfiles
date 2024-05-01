local M = {
	"zbirenbaum/copilot.lua",
	event = "BufReadPre",
	opts = {
		cmd = "Copilot",
		event = "InsertEnter",
		config = function()
			require("copilot").setup({
				suggestion = {
					keymap = {
						accept = "<M-l>",
						accept_word = false,
						accept_line = false,
						next = "<M-]>",
						prev = "<M-[>",
					},
				},
				filetypes = {
					yaml = true,
				},
			})
		end,
	},
}

return M

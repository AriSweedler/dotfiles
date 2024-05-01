local M = {
	"lewis6991/gitsigns.nvim",
	event = "BufReadPre",
	opts = {
		numhl = true,
		on_attach = require("plugins.gitsigns.config").on_attach_hook, -- set up keymaps
		worktrees = {
			{ -- My dotfiles
				toplevel = vim.env.HOME,
				gitdir = vim.env.HOME .. "/dotfiles",
			},
		},
	},
}

return M

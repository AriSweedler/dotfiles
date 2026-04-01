vim.pack.add({ "https://github.com/lewis6991/gitsigns.nvim" })

require("gitsigns").setup({
	numhl = true,
	on_attach = require("ari.gitsigns").on_attach_hook,
	signs_staged_enable = false,
	worktrees = {
		{
			toplevel = vim.env.HOME,
			gitdir = vim.env.HOME .. "/dotfiles",
		},
	},
})

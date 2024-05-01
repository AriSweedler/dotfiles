local M = {
	"folke/todo-comments.nvim",
	event = "VimEnter",
	dependencies = { "nvim-lua/plenary.nvim" },
	opts = {
		keywords = {
			ERROR = { icon = " ", color = "error" },
			ARISWEEDLER_TODO = { icon = " ", color = "warning" },
		},
		signs = false,
	},
	on_attach = function()
		local tc = require("todo-comments")
		vim.keymap.set("n", "]]t", tc.jump_next, { desc = "Next todo comment" })
		vim.keymap.set("n", "[[t", tc.jump_prev, { desc = "Previous todo comment" })
	end,
}

return M

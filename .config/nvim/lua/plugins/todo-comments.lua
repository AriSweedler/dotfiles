local Snacks = require("snacks")

local M = {
	"folke/todo-comments.nvim",
	event = "VimEnter",
	dependencies = { "nvim-lua/plenary.nvim" },
	opts = {
		keywords = {
			ERROR = { icon = " ", color = "error" },
			ARISWEEDLER_TODO = { icon = " ", color = "warning" },
			STINKY = { icon = " ", color = "warning" },
		},
		signs = false,
	},
	config = function(_, opts)
		local tc = require("todo-comments")
		tc.setup(opts)

		vim.keymap.set("n", "]]t", tc.jump_next, { desc = "Todo Comment: Next" })
		vim.keymap.set("n", "[[t", tc.jump_prev, { desc = "Todo Comment: Prev" })
	end,
	keys = {
		{
			"<Leader>pt",
			function()
				Snacks.picker.todo_comments({
					dirs = { vim.api.nvim_buf_get_name(0) },
				})
			end,
			desc = "Snacks Picker: Todos in buffer",
		},
		{
			"<Leader>pT",
			function()
				Snacks.picker.todo_comments()
			end,
			desc = "Snacks Picker: All Todos",
		},
	},
}

return M

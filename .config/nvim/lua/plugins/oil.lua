local M = {
	"stevearc/oil.nvim",
	event = "VeryLazy",
	config = function()
		require("oil").setup({
			columns = { "icon" },
			default_file_explorer = true,
			view_options = {
				show_hidden = true,
				is_always_hidden = function(name, bufnr)
					always_hidden_files = {
						".git",
						".DS_Store",
					}
					return vim.tbl_contains(always_hidden_files, name)
				end,
			},
		})

		-- Open parent directory in floating window
		vim.keymap.set("n", "-", require("oil").toggle_float, { desc = "[Oil] Open floating window" })
	end,
}

return M

local M = {
	"stevearc/oil.nvim",
	event = "VeryLazy",
	opts = {
		columns = { "icon" },
		default_file_explorer = true,
		keymaps = {
			["<Esc>"] = {
				"actions.close",
				desc = "Close oil",
				mode = "n",
			},
			["<C-T><C-T>"] = {
				"actions.select",
				opts = { tab = true },
				desc = "Open the entry in a new tab",
			},
			["<C-V><C-V>"] = {
				"actions.select",
				opts = { vertical = true },
				desc = "Open the entry in a vertical split",
			},
			["<C-S><C-S>"] = {
				"actions.select",
				opts = { horizontal = true },
				desc = "Open the entry in a horizontal split",
			},
		},
		view_options = {
			show_hidden = true,
			is_always_hidden = function(name, _)
				local always_hidden_files = {
					".git",
					".DS_Store",
					"__pycache__",
				}
				return vim.tbl_contains(always_hidden_files, name)
			end,
		},
	},
	config = function(_, opts)
		-- Set up oil.nvim
		require("oil").setup(opts)

		-- Open parent directory in floating window
		vim.keymap.set("n", "-", require("oil").toggle_float, { desc = "[Oil] Open floating window" })
	end,
}

return M

local builtin = require("telescope.builtin")

-- 	opts = {
-- 		defaults = {
-- 			-- TODO these mappings don't work!
-- 			mappings = {
-- 				i = {
-- 					["<ESC>"] = require("telescope.actions").close,
-- 					["<C-;>"] = require("telescope.actions").send_to_loclist
-- 						+ require("telescope.actions").open_loclist,
-- 				},
-- 			},
-- 		},
-- 	},

-- Enable telescope fzf native, if installed
pcall(require("telescope").load_extension, "fzf")
pcall(require("telescope").load_extension, "ui-select")

-- Find files relevant to editing
vim.keymap.set("n", "<Leader>?", builtin.oldfiles, { desc = "[?] Find recently opened files" })
vim.keymap.set("n", "<C-b>", builtin.buffers, { desc = "[ ] Find existing buffers" })
vim.keymap.set("n", "<C-t>", builtin.git_files, { desc = "Search git files" })

-- Find files relevant to folders
vim.keymap.set("n", "<Leader><C-t>", builtin.find_files, { desc = "Search pwd files" })
vim.keymap.set("n", "<Leader><C-v>", function()
	builtin.find_files({
		cwd = vim.fn.stdpath("config"),
	})
end, { desc = "Search VIMRC files" })

-- Find open file
vim.keymap.set("n", "<Leader>S/", function()
	builtin.live_grep({
		grep_open_files = true,
		prompt_title = "Live Grep in Open Files",
	})
end, { desc = "[S]earch [/] in Open Files" })

-- Search through this file
vim.keymap.set("n", "<Leader>/", function()
	-- You can pass additional configuration to telescope to change theme, layout, etc.
	builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
		winblend = 10,
		previewer = false,
	}))
end, { desc = "[/] Fuzzily search in current buffer" })

-- Search through project
vim.keymap.set("n", "<Leader>Sg", builtin.live_grep, { desc = "[S]earch by [G]rep" })
vim.keymap.set("n", "<Leader>Sw", builtin.grep_string, { desc = "[S]earch current [W]ord" })

-- Search through misc
vim.keymap.set("n", "<Leader>St", builtin.builtin, { desc = "[S]earch [T]elescope" })
vim.keymap.set("n", "<Leader>Sh", builtin.help_tags, { desc = "[S]earch [H]elp" })
vim.keymap.set("n", "<Leader>Sd", builtin.diagnostics, { desc = "[S]earch [D]iagnostics" })
vim.keymap.set("n", "<Leader>Sk", builtin.keymaps, { desc = "[S]earch [K]eymaps" })

-- Control
vim.keymap.set("n", "<Leader>Sr", builtin.resume, { desc = "[S]earch [R]esume" })

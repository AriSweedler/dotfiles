-- Search through stuff - <Leader>S
local builtin = require("telescope.builtin")

local dd = require("telescope.themes").get_dropdown({
	winblend = 10,
	previewer = false,
})

-- Search in this file
vim.keymap.set("n", "<Leader>S.", function()
	builtin.current_buffer_fuzzy_find(dd)
end, { desc = "[S]earch in current buffer" })

-- Search in open files
vim.keymap.set("n", "<Leader>So", function()
	builtin.live_grep(dd, {
		grep_open_files = true,
		prompt_title = "Live Grep in Open Files",
	})
end, { desc = "[S]earch in [o]pen Files" })

-- Search in this project
vim.keymap.set("n", "<Leader>Sg", builtin.live_grep, { desc = "[S]earch by [G]rep" })
vim.keymap.set("n", "<Leader>Sw", builtin.grep_string, { desc = "[S]earch current [W]ord" })

-- Search through misc stuff
vim.keymap.set("n", "<Leader>Sd", builtin.diagnostics, { desc = "[S]earch [D]iagnostics" })
vim.keymap.set("n", "<Leader>Sk", builtin.keymaps, { desc = "[S]earch [K]eymaps" })
vim.keymap.set("n", "<Leader>Sm", builtin.marks, { desc = "[S]earch through [m]arks" })
vim.keymap.set("n", "<Leader>Sh", builtin.help_tags, { desc = "[S]earch through [h]elp" })

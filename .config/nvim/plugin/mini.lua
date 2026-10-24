vim.pack.add({ "https://github.com/echasnovski/mini.nvim" })

require("mini.ai").setup({ n_lines = 500 })

-- Default keymaps: sa (add), sd (delete), sr (replace), sf/sF (find), sh (highlight)
require("mini.surround").setup({
	highlight_duration = 1500,
	mappings = {
		suffix_last = "p",
	},
	respect_selection_type = true,
})

require("mini.jump").setup({
	delay = {
		highlight = 250,
		idle_stop = 3000,
	},
})

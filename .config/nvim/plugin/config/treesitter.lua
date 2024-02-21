-- Defer Treesitter setup after first render to improve startup time of 'nvim {filename}'
vim.defer_fn(function()
	require("nvim-treesitter.configs").setup({
		ensure_installed = {
			"bash",
			"c",
			"cpp",
			"go",
			"javascript",
			"lua",
			"markdown",
			"python",
			"rust",
			"tsx",
			"typescript",
			"vim",
			"vimdoc",
		},
		auto_install = true,
		sync_install = true,
		ignore_install = {},
		modules = {},
		highlight = { enable = true },
		indent = { enable = true },
		incremental_selection = {
			enable = true,
			keymaps = {
				init_selection = "<C-Space>",
				node_incremental = "<C-Space>",
				node_decremental = "<M-Space>",
				scope_incremental = "<C-S>",
			},
		},
		-- Define capture groups in 'VIMDIR/queries/{lang}/textobjects.scm'
		--
		-- The 'nvim-treesitter-textobjects' installs a ton of useful queries,
		-- making this system really powerful
		textobjects = {
			select = {
				enable = true,
				lookahead = true,
				keymaps = {
					["aa"] = "@parameter.outer",
					["ia"] = "@parameter.inner",
					["af"] = "@function.outer",
					["if"] = "@function.inner",
					["ac"] = "@class.outer",
					["ic"] = "@class.inner",
				},
			},
			move = {
				enable = true,
				set_jumps = true, -- whether to set jumps in the jumplist
				goto_next_start = {
					["]m"] = "@function.outer",
					["]]"] = "@class.outer",
				},
				goto_next_end = {
					["]M"] = "@function.outer",
					["]["] = "@class.outer",
				},
				goto_previous_start = {
					["[m"] = "@function.outer",
					["[["] = "@class.outer",
				},
				goto_previous_end = {
					["[M"] = "@function.outer",
					["[]"] = "@class.outer",
				},
			},
		},
	})
end, 0)

vim.pack.add({
	"https://github.com/nvim-treesitter/nvim-treesitter",
	"https://github.com/nvim-treesitter/nvim-treesitter-textobjects",
})

local ts = require("nvim-treesitter")

local ensure_installed = { "bash", "lua", "vim", "vimdoc", "query", "python", "javascript", "typescript", "tsx", "go", "yaml" }
local installed = ts.get_installed()
local missing = vim.tbl_filter(function(lang)
	return not vim.list_contains(installed, lang)
end, ensure_installed)
if #missing > 0 then
	ts.install(missing)
end

ts.setup({
	textobjects = {
		select = {
			enable = true,
			lookahead = true,
			keymaps = {
				["aa"] = "@parameter.outer",
				["ia"] = "@parameter.inner",
				["af"] = "@function.outer",
				["if"] = "@function.inner",
			},
			include_surrounding_whitespace = true,
		},
		swap = {
			enable = true,
			swap_next = { ["<Leader>]a"] = "@parameter.inner" },
			swap_previous = { ["<Leader>[a"] = "@parameter.inner" },
		},
		move = {
			enable = true,
			set_jumps = true,
			goto_previous_start = { ["[m"] = "@function.outer", ["[a"] = "@parameter.outer" },
			goto_previous_end   = { ["[M"] = "@function.outer", ["[A"] = "@parameter.outer" },
			goto_next_start     = { ["]m"] = "@function.outer", ["]a"] = "@parameter.outer" },
			goto_next_end       = { ["]M"] = "@function.outer", ["]A"] = "@parameter.outer" },
		},
	},
})

-- Use built-in treesitter for highlighting, indentation, and folding
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("TreeSitterBuiltins", { clear = true }),
	pattern = "*",
	callback = function()
		if not vim.treesitter.get_parser(0, nil, { error = false }) then return end
		vim.treesitter.start()
		vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		vim.wo.foldmethod = "expr"
		vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
	end,
})

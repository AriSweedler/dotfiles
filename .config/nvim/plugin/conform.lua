vim.pack.add({ "https://github.com/stevearc/conform.nvim" })

local prettier = { "prettierd", "prettier", stop_after_first = true }
require("conform").setup({
	notify_on_error = false,
	format_on_save = function(bufnr)
		local disable_filetypes = { c = true, cpp = true }
		if disable_filetypes[vim.bo[bufnr].filetype] then
			return nil
		end
		return {
			timeout_ms = 1000,
			lsp_format = "first",
		}
	end,
	formatters_by_ft = {
		lua = { "stylua" },
		javascript = prettier,
		typescript = prettier,
		javascriptreact = prettier,
		typescriptreact = prettier,
		python = { "autopep8" },
	},
	formatters = {
		autopep8 = {
			args = { "--aggressive", "--aggressive", "-" },
		},
	},
})

vim.keymap.set("", "<Leader>f", function()
	require("conform").format({ async = true, lsp_format = "fallback" })
end, { desc = "[F]ormat buffer" })

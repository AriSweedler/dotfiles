local M = {
	"stevearc/conform.nvim",
	event = "BufReadPre",
	opts = {
		notify_on_error = false,
		format_on_save = {
			timeout_ms = 500,
			lsp_fallback = true,
		},
		formatters_by_ft = {
			lua = { "stylua" },
			-- python = { "black" },
		},
	},
}

return M

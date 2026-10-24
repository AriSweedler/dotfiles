vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = { "*.tftpl" },
	callback = function()
		vim.bo.filetype = "rego"
	end,
})

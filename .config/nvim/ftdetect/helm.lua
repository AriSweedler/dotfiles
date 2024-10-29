vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = "*helm/templates/*.yaml",
	callback = function()
		vim.bo.filetype = "helm"
	end,
})

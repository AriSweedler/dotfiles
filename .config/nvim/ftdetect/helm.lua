vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = { "*helm/templates/*.yaml", "*helm/templates/*.tpl" },
	callback = function()
		vim.bo.filetype = "helm"
	end,
})

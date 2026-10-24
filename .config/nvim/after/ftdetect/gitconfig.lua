vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = { "*.gitconfig" },
	callback = function()
		vim.bo.filetype = "gitconfig"
	end,
})

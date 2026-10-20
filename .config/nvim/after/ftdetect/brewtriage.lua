-- `dotfiles brew triage --edit` writes its plan as triage-plan.brewtriage (syntax/brewtriage.vim).
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = { "*.brewtriage" },
	callback = function()
		vim.bo.filetype = "brewtriage"
	end,
})

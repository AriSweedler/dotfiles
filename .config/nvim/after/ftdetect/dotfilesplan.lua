-- Every `dotfiles … --edit` plan is filetype dotfilesplan (syntax/dotfilesplan.vim): by its first
-- line, `# dotfiles-plan: …` (lib/plan.zsh writes it), or by the extensions the plans use.
vim.filetype.add({
	extension = {
		dfplan = "dotfilesplan",
		brewtriage = "dotfilesplan",
		dfstatus = "dotfilesplan",
		dfpull = "dotfilesplan",
		dfpush = "dotfilesplan",
		dfinit = "dotfilesplan",
		dfapply = "dotfilesplan",
		dfcheck = "dotfilesplan",
	},
})

-- The first line wins over any extension: a plan saved as .txt or with none is still a plan.
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = "*",
	callback = function(args)
		local first = vim.api.nvim_buf_get_lines(args.buf, 0, 1, false)[1] or ""
		if first:find("^# dotfiles%-plan:") then
			vim.bo[args.buf].filetype = "dotfilesplan"
		end
	end,
})

-- Claude Code's editor buffer (ctrl+g) is a tmp file named claude-prompt-<uuid>.md.
-- The claude component layers skill + @-file-reference highlighting on top of markdown.
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = { "claude-prompt-*.md" },
	callback = function()
		vim.bo.filetype = "markdown.claude"
	end,
})

-- Without this, treesitter can't resolve a parser for the compound filetype and
-- the buffer would lose regular markdown highlighting.
vim.treesitter.language.register("markdown", "markdown.claude")

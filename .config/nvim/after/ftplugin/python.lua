require("lspconfig").pyright.setup({})

vim.o.textwidth = 0 -- Unset textwidth

vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"

-- make a mapping for '!' that when it is pressed, we take the logline on the
-- current line (logger.{debug,info,warn,error}) and cycle the severity to be 1
-- higher than it was before. Or we wrap around to the start. Use a function

vim.cmd("command! FormatCommand PyrightOrganizeImports")

-- Mess with the LSP?
vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local lsp_client = vim.lsp.get_active_clients({ bufnr = vim.api.nvim_get_current_buf() })[1]
		if lsp_client ~= nil then
			local lsp_descr = "name=" .. lsp_client.name .. " " .. "id=" .. lsp_client.id
			print("Python LSP attached: " .. lsp_descr)
		end

		local augroup = vim.api.nvim_create_augroup
		local autocmd = vim.api.nvim_create_autocmd
		augroup("__formatter__", { clear = true })
		autocmd("BufWrite", {
			group = "__formatter__",
			command = ":FormatCommand",
			buffer = vim.api.nvim_get_current_buf(),
		})
	end,
})

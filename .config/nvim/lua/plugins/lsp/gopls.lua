require("lspconfig").gopls.setup({})
-- Turn this off
vim.lsp.handlers["textDocument/codeLens"] = function() end
print("Prepared LSP config for gopls")

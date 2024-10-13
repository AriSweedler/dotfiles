local M = {}

local ts_b = require("telescope.builtin")
M.on_attach = function(_, bufnr)
	local bufmap = function(keys, func, desc)
		vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "LSP: " .. desc })
	end

	-- Like what 'K' does
	bufmap("<C-k>", vim.lsp.buf.signature_help, "Signature Documentation")
	bufmap("K", vim.lsp.buf.hover, "Hover documendation")

	-- Navigation
	bufmap("gd", ts_b.lsp_definitions, "[G]oto [D]efinition")
	bufmap("gtd", ts_b.lsp_type_definitions, "[G]oto Type [D]efinition")
	bufmap("gr", ts_b.lsp_references, "[G]oto [R]eferences")
	bufmap("gI", ts_b.lsp_implementations, "[G]oto [I]mplementation")
	bufmap("<Leader>Ssd", ts_b.lsp_document_symbols, "[S]ymbol[s] in [D]ocument")
	bufmap("<Leader>Ssw", ts_b.lsp_dynamic_workspace_symbols, "[S]ymbol[s] in [W]orkspace")

	-- Format
	vim.api.nvim_buf_create_user_command(0, "LspFormat", function(_)
		vim.lsp.buf.format()
	end, { desc = "Format current buffer with LSP" })

	-- Diagnostics
	bufmap("<Leader>Do", vim.diagnostic.open_float, "Open floating diagnostic message")
	bufmap("<Leader>Dq", vim.diagnostic.setloclist, "Open diagnostics list")
	bufmap("<Leader>D?", function()
		vim.cmd("map <Leader>D")
	end, "Show diagnostics keymaps")

	-- Actions
	bufmap("<Leader>rn", vim.lsp.buf.rename, "[R]e[n]ame") -- Rename the variable under your cursor
	bufmap("<Leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")

	-- Commands to dump information
	vim.api.nvim_buf_create_user_command(0, "LspWorkspaceFolders", function()
		print("LSP workspace folders: " .. vim.inspect(vim.lsp.buf.list_workspace_folders()))
	end, { desc = "List LSP workspace folders" })
	vim.api.nvim_buf_create_user_command(0, "LspLog", function()
		vim.cmd.tabedit(vim.lsp.get_log_path())
	end, { desc = "Open LSP log" })
end

-- 'cmp_nvim_lsp' gives additional LSP client capabilities. You can take the
-- defaults, and override them like so:
-- local capabilities = vim.lsp.protocol.make_client_capabilities()
-- M.capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)
--
-- Or you can just take what cmp_nvim_lsp says you have without overrides:
-- M.capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)
--
-- I think I wanna do it deliberately in each 'lua/ari/lsp' file

return M

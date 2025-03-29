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
	bufmap("gtd", ts_b.lsp_type_definitions, "[G]oto Type [D]efinition")
	bufmap("grr", ts_b.lsp_references, "[G]oto [R]eferences")
	bufmap("gI", ts_b.lsp_implementations, "[G]oto [I]mplementation")
	bufmap("<Leader>Ssd", ts_b.lsp_document_symbols, "[S]ymbol[s] in [D]ocument")
	bufmap("<Leader>Ssw", ts_b.lsp_dynamic_workspace_symbols, "[S]ymbol[s] in [W]orkspace")

	-- <C-]> but in a new tab
	bufmap("<Leader><C-]>", function(_)
		local feedme = function(str)
			local key = vim.api.nvim_replace_termcodes(str, true, false, true)
			vim.api.nvim_feedkeys(key, "n", false)
		end
		vim.cmd("tabnew")
		feedme("<C-o><C-]>zO")
	end, "Open definition in new tab")

	-- Format
	vim.api.nvim_buf_create_user_command(0, "LspFormat", function(_)
		vim.lsp.buf.format()
	end, { desc = "Format current buffer with LSP" })

	-- Diagnostics
	bufmap("<Leader>do", vim.diagnostic.open_float, "Open floating diagnostic message")
	bufmap("<Leader>dq", vim.diagnostic.setloclist, "Open buffer diagnostics list")
	bufmap("<Leader><Leader>dq", function()
		vim.diagnostic.setloclist({ severity = vim.diagnostic.severity.ERROR })
	end, "Open buffer diagnostics list only for Errors")
	bufmap("<Leader>da", vim.lsp.buf.code_action, "[d]iagnostic [A]ction")
	bufmap("<Leader>d?", function()
		vim.cmd("map <Leader>d")
	end, "Show diagnostics keymaps")

	-- Actions
	bufmap("grn", vim.lsp.buf.rename, "Rename the variable under your cursor")
	-- show code actions

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

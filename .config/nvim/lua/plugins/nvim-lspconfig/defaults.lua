local M = {}

local function lsp_workspace_folders()
	for _, client in pairs(vim.lsp.get_clients({ bufnr = 0 })) do
		--      • {workspace_folders}     (`lsp.WorkspaceFolder[]?`) The workspace
		--                                folders configured in the client when the
		--                                server starts. This property is only available
		--                                if the client supports workspace folders. It
		--                                can be `null` if the client supports workspace
		--                                folders but none are configured.
		local folder_names_table = {}
		for _, folder in ipairs(client.workspace_folders) do
			table.insert(folder_names_table, folder.name)
		end
		local folder_names = table.concat(folder_names_table, ", ")
		local client_name_padded = client.name .. string.rep(" ", 10 - #client.name)
		print("LSP workspace folders for " .. client_name_padded .. ": " .. folder_names)
	end
end

-- TODO: Use and conform to nvim 0.11.0 defaults instead of writing my own

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
	bufmap("gfu", ts_b.lsp_function_usages, "[G]oto [F]unction [U]sages")

	-- <C-]> but in a new tab
	bufmap("<Leader><C-]>", function(_)
		local feedme = function(str)
			local key = vim.api.nvim_replace_termcodes(str, true, false, true)
			vim.api.nvim_feedkeys(key, "n", false)
		end
		feedme("<C-W><C-]><C-W>T")
	end, "Open definition in new tab")

	-- Format
	vim.api.nvim_buf_create_user_command(0, "LspFormat", function(_)
		vim.lsp.buf.format()
	end, { desc = "Format current buffer with LSP" })

	-- Diagnostics
	bufmap("<Leader>do", vim.diagnostic.setloclist, "Open buffer diagnostics in loclist")
	bufmap("<Leader>dO", vim.diagnostic.open_float, "Open floating diagnostic message")
	bufmap("<Leader>dqq", vim.diagnostic.setqflist, "Open buffer diagnostics in quickfix lust")
	bufmap("<Leader>dQq", function()
		vim.diagnostic.setqflist({ severity = vim.diagnostic.severity.ERROR })
	end, "Open buffer diagnostics list only for Errors")
	bufmap("<Leader>dql", vim.diagnostic.setloclist, "Open buffer diagnostics loclist")
	bufmap("<Leader>dQl", function()
		vim.diagnostic.setloclist({ severity = vim.diagnostic.severity.ERROR })
	end, "Open buffer diagnostics list only for Errors")
	bufmap("<Leader>dd?", function()
		vim.cmd("map <Leader>dd")
	end, "Show diagnostics keymaps")

	-- Actions
	bufmap("<Leader>ca", vim.lsp.buf.code_action, "[c]ode [a]ction")
	bufmap("grn", vim.lsp.buf.rename, "Rename the variable under your cursor")

	-- Commands to dump information
	vim.api.nvim_buf_create_user_command(
		0,
		"LspWorkspaceFolders",
		lsp_workspace_folders,
		{ desc = "List LSP workspace folders" }
	)
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

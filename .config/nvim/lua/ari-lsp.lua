local M = {}

local dump_buffer_info = function()
	local lsp_client = vim.lsp.get_active_clients({ bufnr = 0 })[1]
	local lsp_descr = "name=" .. lsp_client.name .. " " .. "id=" .. lsp_client.id
	print("LSP attached...: " .. lsp_descr)
end

local _nmap = function(keys, func, desc, bufnr)
	if desc then
		desc = "LSP: " .. desc
	end

	vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
end

--  This function gets run when an LSP connects to a particular buffer.
function M.on_attach(_, bufnr)
	dump_buffer_info()
	local nmap = function(keys, func, desc)
		_nmap(keys, func, desc, bufnr)
	end

	nmap("<Leader>rn", vim.lsp.buf.rename, "[R]e[n]ame")
	nmap("<Leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")

	nmap("gd", require("telescope.builtin").lsp_definitions, "[G]oto [D]efinition")
	nmap("gR", require("telescope.builtin").lsp_references, "[G]oto [R]eferences")
	nmap("gI", require("telescope.builtin").lsp_implementations, "[G]oto [I]mplementation")
	nmap("<Leader>D", require("telescope.builtin").lsp_type_definitions, "Type [D]efinition")
	nmap("<Leader>ds", require("telescope.builtin").lsp_document_symbols, "[D]ocument [S]ymbols")
	nmap("<Leader>ws", require("telescope.builtin").lsp_dynamic_workspace_symbols, "[W]orkspace [S]ymbols")

	-- See `:help K` for why this keymap
	nmap("K", vim.lsp.buf.hover, "Hover Documentation")
	nmap("<C-k>", vim.lsp.buf.signature_help, "Signature Documentation")

	-- Lesser used LSP functionality
	nmap("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
	nmap("<Leader>wa", vim.lsp.buf.add_workspace_folder, "[W]orkspace [A]dd Folder")
	nmap("<Leader>wr", vim.lsp.buf.remove_workspace_folder, "[W]orkspace [R]emove Folder")
	nmap("<Leader>wl", function()
		print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
	end, "[W]orkspace [L]ist Folders")

	-- Create a command `:Format` local to the LSP buffer
	vim.api.nvim_buf_create_user_command(bufnr, "Format", function(_)
		vim.lsp.buf.format()
	end, { desc = "Format current buffer with LSP" })
end

return M

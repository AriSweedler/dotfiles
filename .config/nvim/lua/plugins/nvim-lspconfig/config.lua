-- Find all the files in './lua/plugins/lsp' and iterate through them -
-- requiring and saving them into an array
local lsp_dir = vim.fn.stdpath("config") .. "/lua/plugins/lsp"
local lsp_files = require("plenary.scandir").scan_dir(lsp_dir, { depth = 1, hidden = true })
local required_tools = {}
for _, file in ipairs(lsp_files) do
	if file:match("%.lua$") then
		-- TODO: would be nice to use plenary.path here
		local tool = file:match("([^/]+)%.lua$")
		require("plugins.lsp." .. tool)
		table.insert(required_tools, tool)
	end
end
print("Required tools: " .. vim.inspect(required_tools))

-- Ensure the servers and tools above are installed
require("mason").setup()
require("mason-lspconfig").setup({ ensure_installed = required_tools })

local map = function(keys, func, desc)
	vim.keymap.set("n", keys, func, { buffer = 0, desc = "LSP: " .. desc })
end

local aucmd_group = vim.api.nvim_create_augroup("ari-lsp-attach", { clear = true })
vim.api.nvim_create_autocmd("LspAttach", {
	desc = "LSP: Set keybindings",
	group = aucmd_group,
	callback = function(event)
		-- Like what 'K' does
		map("<C-k>", vim.lsp.buf.signature_help, "Signature Documentation")

		-- Navigation
		map("gd", require("telescope.builtin").lsp_definitions, "[G]oto [D]efinition")
		map("gtd", require("telescope.builtin").lsp_type_definitions, "[G]oto Type [D]efinition")
		map("gr", require("telescope.builtin").lsp_references, "[G]oto [R]eferences")
		map("gI", require("telescope.builtin").lsp_implementations, "[G]oto [I]mplementation")
		map("<Leader>Ssd", require("telescope.builtin").lsp_document_symbols, "[S]ymbol[s] in [D]ocument")
		map("<Leader>Ssw", require("telescope.builtin").lsp_dynamic_workspace_symbols, "[S]ymbol[s] in [W]orkspace")

		-- Diagnostics
		map("<Leader>Do", vim.diagnostic.open_float, "Open floating diagnostic message")
		map("<Leader>Dq", vim.diagnostic.setloclist, "Open diagnostics list")
		map("<Leader>D?", function()
			vim.cmd("map <Leader>D")
		end, "Show diagnostics keymaps")

		-- Actions
		map("<Leader>rn", vim.lsp.buf.rename, "[R]e[n]ame") -- Rename the variable under your cursor
		map("<Leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")

		-- Commands to dump information
		vim.api.nvim_buf_create_user_command(0, "LspWorkspaceFolders", function()
			print("LSP workspace folders: " .. vim.inspect(vim.lsp.buf.list_workspace_folders()))
		end, { desc = "List LSP workspace folders" })
		vim.api.nvim_buf_create_user_command(0, "LspLog", function()
			vim.cmd.tabedit(vim.lsp.get_log_path())
		end, { desc = "Open LSP log" })
		vim.api.nvim_buf_create_user_command(0, "LspFormat", function(_)
			vim.lsp.buf.format()
		end, { desc = "Format current buffer with LSP" })
	end,
})

vim.api.nvim_create_autocmd("LspAttach", {
	desc = "LSP: Enable inlay hints",
	group = aucmd_group,
	callback = function(event)
		local id = vim.tbl_get(event, "data", "client_id")
		local client = id and vim.lsp.get_client_by_id(id)
		if client == nil or not client.supports_method("textDocument/inlayHint") then
			return
		end

		-- warning: this api is not stable yet
		vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
	end,
})

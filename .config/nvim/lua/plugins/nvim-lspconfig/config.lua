-- A tool is required if we have a file in lsp_dir
local lsp_dir = vim.fn.stdpath("config") .. "/lua/ari/lsp"
local required_tools = {}

-- Each LSP can give a setup handler. This will let it configure the language
-- server on startup, expose additional capabilities, and so on
local defaults = require("plugins.nvim-lspconfig.defaults")
local default_setup_handler = function(server_name)
	require("lspconfig")[server_name].setup {
		on_attach = defaults.on_attach,
		capabilities = defaults.capabilities
	}
end
local setup_handlers = { default_setup_handler }

-- Add to required_tools and to setup_handlers if the lsp_dir says so
local lsp_files = require("plenary.scandir").scan_dir(lsp_dir, { depth = 1, hidden = true })
for _, file in ipairs(lsp_files) do
	if file:match("%.lua$") then
		local tool = file:match("([^/]+)%.lua$")
		local my_lsp_definition = require("ari.lsp." .. tool)
		table.insert(required_tools, tool)
		table.insert(setup_handlers, my_lsp_definition.setup)
	end
end

-- Ensure the servers and tools above are installed
require("mason").setup()
require("mason-lspconfig").setup({ ensure_installed = required_tools })
require("mason-lspconfig").setup_handlers(setup_handlers)

-- Ensure the servers and tools above are installed
local gtn = require("plugins.nvim-lspconfig.get_tool_name").get_tool_names

require("mason").setup()
require("mason-lspconfig").setup({ ensure_installed = gtn("ari/lsp") })

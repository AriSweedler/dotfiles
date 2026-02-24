-- /Users/arisweedler/.config/nvim/lsp/typescript.lua
local format_settings = {
  insertSpaceAfterOpeningAndBeforeClosingNonemptyBraces = false,
}

return {
  cmd = { "typescript-language-server", "--stdio" },
  filetypes = {
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
  },
  root_markers = {
    "package.json",
    "tsconfig.json",
    "jsconfig.json",
    ".git",
  },
  single_file_support = true,
  -- 🚫 Ensure tsserver never claims formatting
  on_attach = function(client, _)
    client.server_capabilities.documentFormattingProvider = false
    client.server_capabilities.documentRangeFormattingProvider = false
  end,
  settings = {
    typescript = {
      format = format_settings, -- harmless; ignored since formatting is disabled
      preferences = {
        importModuleSpecifierPreference = "non-relative",
        includePackageJsonAutoImports = "auto",
      },
    },
    javascript = {
      format = format_settings, -- harmless; ignored since formatting is disabled
    },
  },
}

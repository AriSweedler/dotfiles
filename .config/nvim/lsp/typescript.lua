local format_settings = {
  insertSpaceAfterOpeningAndBeforeClosingNonemptyBraces = false,
}

return {
  -- Command to start the language server
  cmd = { "typescript-language-server", "--stdio" },

  -- Filetypes this LSP should attach to
  filetypes = {
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact"
  },

  -- Root directory markers - LSP will look for these to determine project root
  root_markers = {
    "package.json",
    "tsconfig.json",
    "jsconfig.json",
    ".git"
  },

  -- Allow single file support (no project needed)
  single_file_support = true,
  settings = {
    typescript = {
      format = format_settings,
      preferences = {
        importModuleSpecifierPreference = "relative",
        includePackageJsonAutoImports = "auto",
      },
    },
    javascript = {
      format = format_settings,
    },
  },
}

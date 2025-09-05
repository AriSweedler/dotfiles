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

--   -- Server-specific settings
--   settings = {
--     typescript = {
--       inlayHints = {
--         includeInlayParameterNameHints = "all",
--         includeInlayParameterNameHintsWhenArgumentMatchesName = false,
--         includeInlayFunctionParameterTypeHints = true,
--         includeInlayVariableTypeHints = true,
--         includeInlayPropertyDeclarationTypeHints = true,
--         includeInlayFunctionLikeReturnTypeHints = true,
--         includeInlayEnumMemberValueHints = true,
--       },
--       suggest = {
--         includeCompletionsForModuleExports = true,
--         includeAutomaticOptionalChainCompletions = true,
--       },
--       preferences = {
--         importModuleSpecifierPreference = "relative",
--         includePackageJsonAutoImports = "auto",
--       },
--     },
--     javascript = {
--       inlayHints = {
--         includeInlayParameterNameHints = "all",
--         includeInlayParameterNameHintsWhenArgumentMatchesName = false,
--         includeInlayFunctionParameterTypeHints = true,
--         includeInlayVariableTypeHints = true,
--         includeInlayPropertyDeclarationTypeHints = true,
--         includeInlayFunctionLikeReturnTypeHints = true,
--         includeInlayEnumMemberValueHints = true,
--       },
--     },
--   },
--
--   -- Custom initialization options
--   init_options = {
--     preferences = {
--       disableSuggestions = false,
--     },
--   },
}

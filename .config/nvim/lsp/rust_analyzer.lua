return {
	cmd = { "rust-analyzer" },
	filetypes = { "rust" },
	single_file_support = true,
	root_markers = { "Cargo.toml", "Cargo.lock", ".git" },
	settings = {
		["rust-analyzer"] = {
			cargo = {
				allFeatures = true,
				loadOutDirsFromCheck = true,
				buildScripts = {
					enable = true,
				},
			},
			checkOnSave = {
				allFeatures = true,
				command = "clippy",
				extraArgs = { "--no-deps" },
			},
			procMacro = {
				enable = true,
				ignored = {
					["async-trait"] = { "async_trait" },
					["napi-derive"] = { "napi" },
					["async-recursion"] = { "async_recursion" },
				},
			},
			inlayHints = {
				bindingModeHints = {
					enable = false,
				},
				chainingHints = {
					enable = true,
				},
				closingBraceHints = {
					enable = true,
					minLines = 25,
				},
				closureReturnTypeHints = {
					enable = "never",
				},
				lifetimeElisionHints = {
					enable = "never",
					useParameterNames = false,
				},
				maxLength = 25,
				parameterHints = {
					enable = true,
				},
				reborrowHints = {
					enable = "never",
				},
				renderColons = true,
				typeHints = {
					enable = true,
					hideClosureInitialization = false,
					hideNamedConstructor = false,
				},
			},
			lens = {
				enable = true,
			},
			hover = {
				actions = {
					enable = true,
				},
			},
			semanticHighlighting = {
				strings = {
					enable = false,
				},
			},
			completion = {
				postfix = {
					enable = true,
				},
				privateEditable = {
					enable = false,
				},
				callable = {
					snippets = "fill_arguments",
				},
			},
		},
	},
}

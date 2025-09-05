return {
	cmd = { "terraform-ls", "serve" },
	filetypes = { "terraform", "terraform-vars", "hcl" },
	single_file_support = true,
	root_markers = {
		".terraform",
		"terraform.tfvars",
		"*.tf",
		".git"
	},
	settings = {
		["terraform-ls"] = {
			rootModules = {},
			excludeRootModules = {},
			experimentalFeatures = {
				validateOnSave = true,
				prefillRequiredFields = true,
			},
			validation = {
				enableEnhancedValidation = true,
			},
		},
	},
}

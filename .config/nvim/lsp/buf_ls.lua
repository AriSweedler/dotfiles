return {
	cmd = { "buf", "beta", "lsp", "--timeout=0", "--log-format=text" },
	filetypes = { "proto" },
	root_markers = {
		"buf.yaml",
		"buf.yml",
		"buf.work.yaml",
		"buf.gen.yaml",
		".git"
	},
	single_file_support = true,
}

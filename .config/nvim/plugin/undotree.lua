vim.o.undofile = true

require("ari.keymap").lazyload({
	key = "<Leader>U",
	packadd = "nvim.undotree",
	cmd = vim.cmd.Undotree,
	desc = "[ari] [lazyload] Toggle undotree",
})

vim.o.undofile = true

require("ari.keymap").lazyload({
	key = "<Leader>U",
	packadd = "nvim.undotree",
	cmd = vim.cmd.UndotreeToggle,
	desc = "[ari] [lazyload] Toggle undotree",
})

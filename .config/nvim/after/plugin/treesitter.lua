vim.keymap.set("n", "<Leader>I", function()
	vim.cmd("InspectTree")
end, { desc = "Open InspectTree" })

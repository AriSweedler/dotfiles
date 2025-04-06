local lmap = function(keys, fxn, desc)
	vim.keymap.set("n", keys, fxn, { buffer = true, desc = "Fugitive: " .. desc })
end

lmap("gP", function()
	vim.cmd("Git push")
end, "Git push")

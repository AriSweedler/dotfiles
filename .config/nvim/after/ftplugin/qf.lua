vim.cmd("packadd cfilter")

local lmap = function(keys, fxn, desc)
	vim.keymap.set("n", keys, fxn, { buffer = true, desc = "Loclist: " .. desc })
end

-- Delete
lmap("D", function()
	vim.cmd("Lfilter! /" .. vim.fn.getreg("/") .. "/")
end, "Delete (filter-out) entries matching search register")

-- Filter-in
lmap("F", function()
	vim.cmd("Lfilter /" .. vim.fn.getreg("/") .. "/")
end, "Select for (filter-in) entries matching search register")

-- undo and redo
lmap("u", function()
	vim.cmd("lolder")
end, "Undo change")

lmap("<C-r>", function()
	vim.cmd("lnewer")
end, "Redo change")

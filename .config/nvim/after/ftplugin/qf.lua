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

-- Remove current line from qflist
--
-- Go bongo mode with this fun 'Shift + Subtract' keymap
lmap("_", function()
	local feedme = function(str)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(str, true, false, true), "m", false)
	end

	-- Remove the current line
	feedme("\\l-")

	-- If the loclist is NOT empty, do some extra stuff
	if #vim.fn.getloclist(0) ~= 1 then
		feedme("<Enter>")
		if vim.fn.foldclosed(vim.api.nvim_win_get_cursor(0)[1]) ~= -1 then
			feedme("zO")
		else
			feedme("zO")
		end
		feedme("zz")
	end

	-- Return to the loclist or close it
	feedme("\\ll")
end, "Remove current line from qflist")

-- Filter in 'func ', filter out '_test' and 'mock'
--
-- Useful for finding golang functions
lmap("ff", function()
	vim.cmd("Lfilter /func /")
	vim.cmd("Lfilter! /_test/")
	vim.cmd("Lfilter! /mock/")
end, "Find functions (golang)")

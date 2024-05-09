vim.o.grepprg = "rg --vimgrep"

local function quickmap(lhs, rhs1, rhs2)
	vim.keymap.set("n", lhs, function()
		local _, err = pcall(function()
			vim.cmd(rhs1)
		end)
		if err then
			vim.cmd(rhs2)
		end
	end, { silent = true })
end

local function quicktoggle(x)
	vim.keymap.set("n", "<Leader>" .. x .. x, function()
		if vim.o.buftype == "quickfix" then
			vim.cmd(x .. "close")
			return
		end

		vim.cmd(x .. "open")
	end)
end

local function quickadd(x)
	vim.keymap.set("n", "<Leader>" .. x .. "+", function()
		-- Figure how to add something to the xlist
		local setxxlist = vim.fn.setqflist
		if x == "l" then
			setxxlist = vim.fn.setloclist
		end

		-- Generate a thing to add from the current column
		local entry = {
			bufnr = vim.api.nvim_get_current_buf(),
			lnum = vim.api.nvim_win_get_cursor(0)[1],
			col = vim.api.nvim_win_get_cursor(0)[2],
			text = vim.api.nvim_get_current_line(),
			type = "I",
		}

		-- Add it to the xlist
		setxxlist(0, {}, "a", { items = { entry } })
	end, { silent = true })
end

local function quickfix_mappings()
	local xlists = {
		l = "l",
		q = "c",
	}
	for k, x in pairs(xlists) do
		quickmap("[" .. k, x .. "prev", x .. "first")
		quickmap("]" .. k, x .. "next", x .. "last")
		quickmap("[" .. k:upper(), x .. "pfile", x .. "first")
		quickmap("]" .. k:upper(), x .. "nfile", x .. "last")
		quickmap("<Leader>[" .. k, x .. "first", x .. "first")
		quickmap("<Leader>]" .. k, x .. "last", x .. "last")
		quicktoggle(x)
		quickadd(x)
	end
end

quickfix_mappings()

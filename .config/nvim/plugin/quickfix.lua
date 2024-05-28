vim.o.grepprg = "rg --vimgrep"

local function quickmap(lhs, rhs1, rhs2)
	vim.keymap.set("n", lhs, function()
		local _, err = pcall(function()
			vim.cmd(rhs1)
		end)
		if err then
			vim.cmd(rhs2)
		end
		-- open folds until you can see the cursor
		vim.cmd("norm! zv")
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
		-- Generate a thing to add from the current column
		local entry = {
			bufnr = vim.api.nvim_get_current_buf(),
			lnum = vim.api.nvim_win_get_cursor(0)[1],
			col = vim.api.nvim_win_get_cursor(0)[2],
			text = vim.api.nvim_get_current_line(),
			type = "I",
		}

		-- Figure how to add something to the xlist
		if x == "l" then
			vim.fn.setloclist(0, {}, "a", { items = { entry } })
		elseif x == "c" then
			vim.fn.setqflist({}, "a", { items = { entry } })
		end
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
		quickmap("<Leader>[" .. k:upper(), x .. "first", x .. "first")
		quickmap("<Leader>]" .. k:upper(), x .. "last", x .. "last")
		quicktoggle(x)
		quickadd(x)
	end
end

quickfix_mappings()

-- If telescope is installed
if pcall(require, "telescope") then
	local t_builtin = require("telescope.builtin")
	vim.keymap.set("n", "<Leader>cT", function()
		t_builtin.quickfix()
	end)
	vim.keymap.set("n", "<Leader>lT", function()
		t_builtin.loclist()
	end)
end

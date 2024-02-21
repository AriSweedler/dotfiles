local M = {}

function M.toggle_llist()
	if vim.o.buftype == "quickfix" then
		vim.cmd("lclose")
		return
	end

	vim.cmd("lopen")
end

function M.toggle_qflist()
	if vim.o.buftype == "quickfix" then
		vim.cmd("cclose")
		return
	end

	vim.cmd("copen")
end

function M.add_curline_llist()
	local loclist_entry = {
		bufnr = vim.api.nvim_get_current_buf(),
		lnum = vim.api.nvim_win_get_cursor(0)[1],
		col = vim.api.nvim_win_get_cursor(0)[2],
		text = vim.api.nvim_get_current_line(),
		type = "I",
	}
	vim.fn.setloclist(0, {}, "a", { items = { loclist_entry } })
end

return M

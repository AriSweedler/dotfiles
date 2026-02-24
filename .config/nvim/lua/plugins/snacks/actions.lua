local M = {}

M.tabedit = function(picker)
	local selections = picker:selected({ fallback = true })
	for _, item in ipairs(selections) do
		if not item.file then
			vim.notify("No file found for keymap: " .. item.text, vim.log.levels.ERROR)
			return
		end
		vim.cmd("tabedit " .. vim.fn.fnameescape(item.file))
		vim.api.nvim_win_set_cursor(0, item.pos)
	end
	picker:close()
end

M.edit_register = function(picker)
	local selections = picker:selected({ fallback = true })
	local item = selections[1]
	if not item or not item.reg then
		vim.notify("No register selected", vim.log.levels.ERROR)
		return
	end
	picker:close()

	local reg = item.reg
	local contents = item.data or ""

	local buf = vim.api.nvim_create_buf(false, true)
	local lines = vim.split(contents, "\n", { plain = true })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local width = math.min(80, vim.o.columns - 4)
	local height = math.min(math.max(#lines, 1) + 1, vim.o.lines - 4)
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " Register \"" .. reg .. "\" ",
		title_pos = "center",
	})

	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "text"

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			vim.fn.setreg(reg, table.concat(new_lines, "\n"))
			vim.bo[buf].modified = false
			vim.notify("Register \"" .. reg .. "\" updated")
		end,
	})
end

return M

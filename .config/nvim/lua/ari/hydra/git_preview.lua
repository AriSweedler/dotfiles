local M = {}

local function get_preview_win()
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if vim.w[winid].gitsigns_preview then
			return winid
		end
	end
end

function M.close()
	local winid = get_preview_win()
	if winid then
		pcall(vim.api.nvim_win_close, winid, true)
	end
end

function M.open_as(cmd, callback)
	local winid = get_preview_win()
	if not winid then return end
	local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(winid), 0, -1, false)
	M.close()
	local src_win = vim.api.nvim_get_current_win()
	vim.cmd(cmd)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "diff"
	if callback then
		callback(buf, src_win)
	end
end

function M.inject_heads(heads)
	require("gitsigns").preview_hunk()
	vim.schedule(function()
		local winid = get_preview_win()
		if not winid then return end
		local buf = vim.api.nvim_win_get_buf(winid)
		local map = function(key, fn)
			vim.keymap.set("n", key, fn, { buffer = buf, nowait = true })
		end
		for _, head in ipairs(heads) do
			local key, fn = head[1], head[2]
			if fn then
				map(key, fn)
			end
		end
		local function on_open(split_buf, src_win)
			vim.keymap.set("n", "q", function()
				pcall(vim.api.nvim_win_close, 0, true)
				pcall(vim.api.nvim_set_current_win, src_win)
			end, { buffer = split_buf, nowait = true })
		end
		map("<C-t>", function() M.open_as("tabnew", on_open) end)
		map("<C-v>", function() M.open_as("vsplit", on_open) end)
		map("<C-s>", function() M.open_as("split", on_open) end)
	end)
end

return M

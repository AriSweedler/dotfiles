local function toggle_view_whitespace()
	vim.wo.list = not vim.wo.list
	-- Prime the next search to find trailing whitespace. Just hit 'n'
	vim.fn.setreg("/", [[\s\+$]])
end

local function clear_whitespace()
	vim.cmd([[silent! %s/\s\+$//e]])
end

local function view_textwrapN()
	print("Setting textwidth to " .. vim.v.count)
	vim.bo.textwidth = vim.v.count
end

local function toggle_view_diffthis()
	local original_win = vim.api.nvim_get_current_win()

	-- Toggle 'diffthis' for all windows
	local windows = vim.api.nvim_tabpage_list_wins(0)
	for _, win in ipairs(windows) do
		vim.api.nvim_set_current_win(win)
		if vim.wo.diff then
			vim.cmd("diffoff")
		else
			vim.cmd("diffthis")
		end
	end

	vim.api.nvim_set_current_win(original_win)
end

-- Set keyboard bindings
vim.keymap.set("n", "<Leader>w", toggle_view_whitespace, { desc = "Toggle list option" })
vim.keymap.set("n", "<Leader><Leader>D", toggle_view_diffthis, { desc = "Toggle diffthis in all windows" })
vim.keymap.set("n", "<Leader>W", clear_whitespace, { desc = "Clear trailing whitespace" })
vim.keymap.set("n", "<Leader>tw", view_textwrapN, { desc = "Set textwidth (accepts v:count)" })

-- And make command bindings
vim.api.nvim_create_user_command("ToggleWhitespace", toggle_view_whitespace, {})
vim.api.nvim_create_user_command("ClearWhitespace", clear_whitespace, {})
vim.api.nvim_create_user_command("DiffThis", toggle_view_diffthis, {})

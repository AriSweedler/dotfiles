local M = {}

local function set_colors()
	-- This is my eye color: #535F69
	vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = "#008800", bg = "#004400" })
	vim.api.nvim_set_hl(0, "GitSignsDelete", { fg = "#aa0000", bg = "#440000" })
	vim.api.nvim_set_hl(0, "GitSignsChange", { fg = "#bbbb00", bg = "#808000" })
end

local function brack_h(bc, fxn)
	return function()
		if vim.wo.diff then
			return bc
		end
		vim.schedule(fxn)
		return "<Ignore>"
	end
end

function M.on_attach_hook(bufnr)
	local function my_map(mode, l, r, opts)
		opts = opts or { noremap = true }
		opts.buffer = bufnr
		vim.keymap.set(mode, l, r, opts)
	end
	local gs = package.loaded.gitsigns

	set_colors()

	-- Navigation
	my_map({ "n", "v" }, "]h", brack_h("]h", gs.next_hunk), { expr = true, desc = "Jump to next hunk" })
	my_map({ "n", "v" }, "[h", brack_h("[h", gs.prev_hunk), { expr = true, desc = "Jump to previous hunk" })

	-- NOTE: ]c is much more ergonomic for me than ]h, so I make this one
	-- exception to the grammar...
	my_map({ "n", "v" }, "]c", brack_h("]c", gs.next_hunk), { expr = true, desc = "Jump to next [c]hunk" })
	my_map({ "n", "v" }, "[c", brack_h("[c", gs.prev_hunk), { expr = true, desc = "Jump to previous [c]hunk" })

	-- Unified hunk staging function
	local function stage_hunk_with_feedback()
		local mode = vim.fn.mode()
		local range

		-- If in visual mode, determine selected line range
		if mode == 'v' or mode == 'V' then
			local start_line = vim.fn.line('.')
			local end_line = vim.fn.line('v')
			if start_line > end_line then
				start_line, end_line = end_line, start_line
			end
			range = { start_line, end_line }
		end

		-- Stage hunk (with or without range)
		if range then
			gs.stage_hunk(range)
		else
			gs.stage_hunk()
		end

		-- Notify and schedule redraw
		-- vim.notify("We will schedule a redraw", vim.log.levels.INFO)
		vim.schedule(function()
			-- vim.notify("Redrawing now", vim.log.levels.INFO)
			vim.api.nvim_command('redraw')
		end)
	end

	-- Hunk actions
	my_map("v", "<Leader>hs", stage_hunk_with_feedback, { desc = "stage git hunk" })
	my_map("v", "<Leader>hr", function()
		gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
	end, { desc = "reset git hunk" })
	my_map("n", "<Leader>hs", stage_hunk_with_feedback, { desc = "stage git hunk" })
	my_map("n", "<Leader>hS", gs.undo_stage_hunk, { desc = "undo stage hunk" })
	my_map("n", "<Leader>hr", gs.reset_hunk, { desc = "git reset hunk" })
	my_map("n", "<Leader>hp", gs.preview_hunk, { desc = "preview git hunk" })
	my_map("n", "<Leader>hb", gs.blame_line, { desc = "git blame line" })

	-- Buffer hunk actions
	my_map("n", "<Leader>hS", gs.stage_buffer, { desc = "git Stage buffer" })
	my_map("n", "<Leader>hR", gs.reset_buffer, { desc = "git Reset buffer" })
	my_map("n", "<Leader>hL", gs.setloclist, { desc = "git Hunks -> loclist" })

	-- diffs (<Leader>hd)
	my_map("n", "<Leader>hdd", gs.diffthis, { desc = "git diff against index" })
	my_map("n", "<Leader>hdD", function()
		gs.diffthis("~")
	end, { desc = "git diff against last commit" })
	my_map("n", "<Leader>hdM", function()
		gs.diffthis("main")
	end, { desc = "git diff against branch main" })

	-- Toggles (<Leader>ht)
	my_map("n", "<Leader>htb", gs.toggle_current_line_blame, { desc = "toggle git blame line" })
	my_map("n", "<Leader>htd", gs.toggle_deleted, { desc = "toggle git show deleted" })
	my_map("n", "<Leader>htl", gs.toggle_linehl, { desc = "toggle git deltas highlighting lines" })

	-- Text object
	my_map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { desc = "select git hunk" })
end

return M

local M = {}

function M.on_attach_hook(bufnr)
	local function my_map(mode, l, r, opts)
		opts = opts or { noremap = true }
		opts.buffer = bufnr
		vim.keymap.set(mode, l, r, opts)
	end

	local function brack_c(bc, fxn)
		return function()
			if vim.wo.diff then
				return bc
			end
			vim.schedule(fxn)
			return "<Ignore>"
		end
	end

	local gs = package.loaded.gitsigns

	-- Navigation
	my_map({ "n", "v" }, "]c", brack_c("]c", gs.next_hunk), { expr = true, desc = "Jump to next hunk" })
	my_map({ "n", "v" }, "[c", brack_c("[c", gs.prev_hunk), { expr = true, desc = "Jump to previous hunk" })

	-- Actions
	-- visual mode
	my_map("v", "<Leader>hs", function()
		gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
	end, { desc = "stage git hunk" })
	my_map("v", "<Leader>hr", function()
		gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
	end, { desc = "reset git hunk" })

	-- normal mode
	my_map("n", "<Leader>hs", gs.stage_hunk, { desc = "git stage hunk" })
	my_map("n", "<Leader>hr", gs.reset_hunk, { desc = "git reset hunk" })
	my_map("n", "<Leader>hu", gs.undo_stage_hunk, { desc = "undo stage hunk" })
	my_map("n", "<Leader>hS", gs.stage_buffer, { desc = "git Stage buffer" })
	my_map("n", "<Leader>hR", gs.reset_buffer, { desc = "git Reset buffer" })
	my_map("n", "<Leader>hp", gs.preview_hunk, { desc = "preview git hunk" })
	my_map("n", "<Leader>hb", function()
		gs.blame_line({ full = false })
	end, { desc = "git blame line" })

	-- diffs
	my_map("n", "<Leader>hd", gs.diffthis, { desc = "git diff against index" })
	my_map("n", "<Leader>hD", function()
		gs.diffthis("~")
	end, { desc = "git diff against last commit" })

	-- Toggles
	my_map("n", "<Leader>tb", gs.toggle_current_line_blame, { desc = "toggle git blame line" })
	my_map("n", "<Leader>td", gs.toggle_deleted, { desc = "toggle git show deleted" })

	-- Text object
	my_map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { desc = "select git hunk" })
end

return M

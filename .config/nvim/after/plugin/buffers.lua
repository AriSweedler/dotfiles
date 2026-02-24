local function vcount_fmt(format_str)
	return function()
		vim.cmd(string.format(format_str, vim.v.count1))
	end
end

-- Move between buffers with [b and ]b
vim.keymap.set("n", "[b", vcount_fmt("%dbprev"))
vim.keymap.set("n", "]b", vcount_fmt("%dbnext"))

-- Break a window to a new tab. I prefer <C-w>! instead of <C-w>T, it's
-- consistent with tmux. And this is one of the few options that I think tmux
-- got better :)
vim.keymap.set("n", "<C-w>!", "<C-w>T")

-- Change tabs
vim.keymap.set("n", "[t", vcount_fmt("%dtabprev"))
vim.keymap.set("n", "]t", function() -- lol
	if pcall(vim.cmd, string.format("tabnext +%d", vim.v.count1)) then return end
	vim.cmd("tabnext")
end)

-- Physically move tabs
vim.keymap.set("n", "<Leader>[t", vcount_fmt("tabmove -%d"))
vim.keymap.set("n", "<Leader>]t", vcount_fmt("tabmove +%d"))
vim.keymap.set("n", "<Leader>[T", ":tabmove 0<CR>")
vim.keymap.set("n", "<Leader>]T", ":tabmove $<CR>")

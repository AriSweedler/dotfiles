local function get_next_scratch_number()
	local buffers = vim.api.nvim_list_bufs()
	local scratch_numbers = {}
	for _, buf in ipairs(buffers) do
		local name = vim.api.nvim_buf_get_name(buf)
		print("We see buf named: " .. name)
		local number = name:match(".Scratch (%d+).")
		if number then
			print("We see scratch buf numbered " .. number)
			scratch_numbers[tonumber(number)] = true
		end
	end

	local n = 1
	while scratch_numbers[n] do
		n = n + 1
	end

	return n
end

local function toggle_scratch()
	if vim.bo.buftype == "nofile" then
		-- if there is a saved name, use it
		if vim.b.buf_name_before_scratch then
			vim.api.nvim_buf_set_name(0, vim.b.buf_name_before_scratch)
		end

		-- undo the 'nofile' buftype
		vim.bo.buftype = ""
		return
	end

	-- Set the buftype to nofile so we can't write to it
	vim.bo.buftype = "nofile"

	-- Save the buffer's name in a buffer-local variable
	vim.b.buf_name_before_scratch = vim.api.nvim_buf_get_name(0)

	-- name the buffer 'scratch_N' where N is the smallest number available
	local n = get_next_scratch_number()
	vim.api.nvim_buf_set_name(0, "[Scratch " .. n .. "]")

	-- Remap <C-f> locally to just mean <Esc>
	vim.keymap.set({ "i", "n" }, "<C-f>", "<Esc>", { buffer = true })
end

-- map 'leader leader S' to toggle if this file is scratch or not
vim.keymap.set("n", "<Leader><Leader>S", toggle_scratch, { desc = "Toggle scratch mode for this file" })

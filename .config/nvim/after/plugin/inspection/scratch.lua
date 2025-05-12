-- Get the next available scratch buffer number
local function get_next_scratch_number()
	local buffers = vim.api.nvim_list_bufs()
	local scratch_numbers = {}

	for _, buf in ipairs(buffers) do
		local name = vim.api.nvim_buf_get_name(buf)
		local number = name:match(".Scratch (%d+).")
		if number then
			scratch_numbers[tonumber(number)] = true
		end
	end

	local n = 1
	while scratch_numbers[n] do
		n = n + 1
	end

	return n
end

-- Toggle between a scratch buffer and a regular buffer
local function toggle_scratch()
	local buftype = vim.bo.buftype

	-- If we're currently in a nofile buffer (i.e., a scratch buffer)
	if buftype == "nofile" then
		-- Restore the original buffer name, if saved
		if vim.b.buf_name_before_scratch then
			vim.api.nvim_buf_set_name(0, vim.b.buf_name_before_scratch)
		end

		-- Undo the 'nofile' buftype
		vim.bo.buftype = ""
	else
		-- Save the current buffer name before converting to scratch
		vim.b.buf_name_before_scratch = vim.api.nvim_buf_get_name(0)

		-- Set the buftype to 'nofile' and give it a unique name
		vim.bo.buftype = "nofile"
		local n = get_next_scratch_number()
		vim.api.nvim_buf_set_name(0, "[Scratch " .. n .. "]")

		-- Remap <C-f> to <Esc> locally for scratch buffers
		vim.keymap.set({ "i", "n" }, "<C-f>", "<Esc>", { buffer = true })
	end
end

-- Map 'leader leader S' to toggle between scratch mode and regular mode
vim.keymap.set("n", "<Leader><Leader>S", toggle_scratch, { desc = "Toggle scratch mode for this file" })

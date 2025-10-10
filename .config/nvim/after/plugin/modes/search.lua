local function slash_escape(word)
	return word
end

local function lgrep_escape(word)
	return word
end

-- TODO: Come up with a set of tests. Each test is a table...
-- * word input
-- * rg output
-- * slash output
-- TODO: How to write an escaping function?
-- * split into individual characters ('a', '^', '<', '*', '\')
-- * escape each one that needs to be escaped (table lookup ==> add a '\')

-- Run lgrep, set the search register, and open the loclist
local function lgrep(word, opts)
	opts = opts or {}
	local cmdTable = {}

	if not opts.verbose then
		table.insert(cmdTable, "silent")
	end

	if opts.add then
		table.insert(cmdTable, "lgrepadd")
	else
		table.insert(cmdTable, "lgrep")
	end

	if not opts.nobang then
		cmdTable[#cmdTable] = cmdTable[#cmdTable] .. "!"
	end

	table.insert(cmdTable, "'" .. lgrep_escape(word) .. "'")
	local cmd = table.concat(cmdTable, " ")

	vim.fn.setreg("/", slash_escape(word))
	vim.cmd("tabnew deleteme")
	vim.cmd(cmd)
	vim.cmd("lopen | wincmd p | lfirst")
	vim.cmd("bdelete! deleteme")
end

-- Get the visually selected text
local function vyank()
	-- Read the two edges of the visual selection
	local _, s_lnum, s_col, _ = unpack(vim.fn.getpos("v"))
	local _, e_lnum, e_col, _ = unpack(vim.fn.getpos("."))

	-- Swap the endpoints if necessary - the 'start' has to come before 'end'
	if s_lnum > e_lnum or (s_lnum == e_lnum and s_col > e_col) then
		s_lnum, e_lnum = e_lnum, s_lnum
		s_col, e_col = e_col, s_col
	end

	-- Get the array of lines, return a single string
	local arr_of_lines = vim.api.nvim_buf_get_text(0, s_lnum - 1, s_col - 1, e_lnum - 1, e_col, {})
	return table.concat(arr_of_lines, "\n")
end

-- Set highlight on search
vim.o.incsearch = true
vim.o.hlsearch = true

-- Use <C-_> to unhighlight stuff
vim.keymap.set("n", "<C-_>", ":nohlsearch<CR>", { silent = true })
vim.keymap.set("i", "<C-_>", "<Esc>:nohlsearch<CR>a", { silent = true })
vim.keymap.set("v", "<C-_>", "<Esc>:nohlsearch<CR>`>", { silent = true })

-- Make '*' better
vim.keymap.set("n", "*", "<Cmd>keepjumps normal! *N<CR>")
vim.keymap.set("v", "*", function()
	local selected = vyank()
	vim.fn.setreg("/", slash_escape(selected))
	vim.api.nvim_input("<Esc>")
end, { silent = true })

-- Go to the END instead of next match
vim.keymap.set("n", "<C-n>", "vgn<Esc>")

-- lgrep on the word under the cursor.
vim.keymap.set("n", "g*", function()
	lgrep(vim.fn.expand("<cword>"))
end, { silent = true })

-- lgrep on the visual selection
vim.keymap.set("v", "g*", function()
	local selected = vyank()
	lgrep(selected)
end, { silent = true })

-- Keymap to invoke lgrep
vim.keymap.set("n", "<C-s>", function()
	-- TODO: catch keyboard interupts - currently <C-c> to cancel logs an error.
	-- But I wanna get canceled silently
	local word = vim.fn.input("lgrep: ")
	if word == "" then
		return
	end

	lgrep(word)
end)

-- Searching in visual move searches just inside the selection. `:help \%V` for
-- the win!!
vim.keymap.set("x", "/", "<Esc>/\\%V")

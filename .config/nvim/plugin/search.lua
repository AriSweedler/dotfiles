-- Run lgrep and set the search register
local function lgrep(word)
	vim.fn.setreg("/", word)
	vim.cmd("lgrep " .. word)
end

-- Get the visually selected text without clobbering any registers
local function vyank()
	local saved = vim.fn.getreg("t")
	vim.api.nvim_feedkeys([["ty]], "n", false)
	local highlighted = vim.fn.getreg("t")
	vim.fn.setreg("t", saved)
	return highlighted
end

-- Set highlight on search
vim.o.incsearch = true
vim.o.hlsearch = true

-- Use <C-_> to unhighlight stuff
vim.keymap.set("n", "<C-_>", ":nohlsearch<CR>", { silent = true })
vim.keymap.set("i", "<C-_>", "<Esc>:nohlsearch<CR>a", { silent = true })
vim.keymap.set("v", "<C-_>", "<Esc>:nohlsearch<CR>`>a", { silent = true })

-- lgrep on the word under the cursor.
vim.keymap.set("n", "g*", function()
	lgrep(vim.fn.expand("<cword>"))
end, { silent = true })

-- lgrep on the visual selection
vim.keymap.set("v", "g*", function()
	lgrep(vyank())
end, { silent = true })

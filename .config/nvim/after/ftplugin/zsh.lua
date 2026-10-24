vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.expandtab = true

local function setreg(name, keys)
	vim.fn.setreg(name, vim.api.nvim_replace_termcodes(keys, true, false, true))
end

setreg('x', "f'a${c_cyan}<C-o>f'${c_rst}<Esc>  ")

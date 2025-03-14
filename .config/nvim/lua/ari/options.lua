vim.g.mapLeader = "\\"
vim.g.maplocalLeader = "\\"

-- Basic config
vim.cmd("colorscheme evening")
vim.o.number = true
vim.o.relativenumber = true

-- Save undo history
vim.o.undofile = true

-- Set clipboard to use the system clipboard
vim.o.clipboard = "unnamedplus"

-- Keep signcolumn on by default
vim.wo.signcolumn = "yes"

vim.o.termguicolors = true

-- Lol no
vim.o.mouse = ""

-- Open new splits to the right
vim.o.splitright = true
vim.o.splitbelow = true

-- Let the terminal set the background color
vim.api.nvim_set_hl(0, "Normal", { bg = "None" })

-- Set listchars for spaces and tabs
vim.opt.listchars = { space = ".", tab = "|>" }

-- Turn 'timeout' off so we have unlimited time to enter mapped commands
vim.o.timeout = false

-- Tell nvim that we've already loaded netrw, so we don't try to load it ever
-- again. This effectively disables netrw
vim.g.loaded_netrwPlugin = 1

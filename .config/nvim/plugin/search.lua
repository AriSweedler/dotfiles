local ari = require("ari")

-- Set highlight on search
vim.o.incsearch = true
vim.o.hlsearch = true

-- Use <C-_> to unhighlight stuff
ari.map("n", "<C-_>", ":nohlsearch<CR>")
ari.map("i", "<C-_>", "<Esc>:nohlsearch<CR>a")
ari.map("v", "<C-_>", "<Esc>:nohlsearch<CR>`>a")

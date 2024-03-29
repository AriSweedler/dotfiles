-- Move between buffers with [b and ]b
-- delete buffers with \bd

local ari = require("ari")

ari.map("n", "[b", ":bprev<Enter>")
ari.map("n", "]b", ":bnext<Enter>")

-- Close buffers
ari.map("n", "<Leader>bc", ":bnext <Bar> :bdelete #<Enter>")
ari.map("n", "<Leader>BC", ":lua vim.api.nvim_buf_delete(0, {})<Enter>")

-- gr to move tabs (gr/gt instead of gT/gt)
ari.map("n", "gr", ":tabprev<Enter>")

-- <C-w>! instead of <C-w>T (Between vim's default and tmux's default, I like
-- tmux's better :] )
ari.map("n", "<C-w>!", "<C-w>T")

-- Physically move tabs
ari.map("n", "<Leader>[t", ":tabmove -<Enter>")
ari.map("n", "<Leader>]t", ":tabmove +<Enter>")
ari.map("n", "<Leader>[T", ":tabmove 0<Enter>")
ari.map("n", "<Leader>]T", ":tabmove $<Enter>")

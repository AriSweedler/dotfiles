local ari = require("ari")

-- Map <C-f> to leave you in normal mode, written
ari.map("i", "<C-f>", "<Esc>:w<Enter>")
ari.map("n", "<C-f>", ":w<Enter>")
ari.map("v", "<C-f>", "<Esc>:w<Enter>")

-- Map <C-g> to quit
ari.map("n", "<C-g>", ":q<Enter>")

-- jk to exit insert
ari.map("i", "jk", "<Esc>")

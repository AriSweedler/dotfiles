local ari = require("ari")

vim.cmd("packadd cfilter")

-- Delete
ari.buf_map("n", "D", ":Lfilter! /<C-r>//<Enter>")

-- Filter-in
ari.buf_map("n", "F", ":Lfilter /<C-r>//<Enter>")

-- undo and redo
ari.buf_map("n", "u", ":lolder<Enter>")
ari.buf_map("n", "<C-r>", ":lnewer<Enter>")

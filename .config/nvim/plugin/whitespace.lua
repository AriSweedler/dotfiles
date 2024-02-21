local ari = require("ari")

-- Map <Leader>w to toggle list option
ari.map("n", "<Leader>w", ":setlocal list!<Enter>:let @/ = '\\s\\+$'<Enter>")

local ari = require("ari")

ari.map("n", "<Leader>j", ":lua require('ari.jenkins').filter_in_colorlogs()<CR>")

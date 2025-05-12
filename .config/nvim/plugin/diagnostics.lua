-- plugin/diagnostics.lua

local d = require("ari.diagnostics")

-- Initialize diagnostics in zen mode
d.setup()

-- Keymap to toggle diagnostics display
vim.keymap.set("n", "<leader>td", d.toggle, {
	desc = "Toggle Diagnostics Display (virtual_text <--> virtual_lines)",
})

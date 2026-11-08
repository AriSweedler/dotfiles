local hydra = require("ari.hydra")
local registered = hydra.setup()

vim.keymap.set('n', '<Leader>??', function() hydra.help(registered) end, { desc = "Show hydra mappings" })

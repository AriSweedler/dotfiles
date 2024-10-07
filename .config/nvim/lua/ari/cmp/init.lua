-- TODO: reflect to read all other files in this dir and source them
require ("ari.cmp.my_completion_source")

-- TODO: Make a function that runs a callback for each lua file in a dir. Use it
-- in '~/.config/nvim/lua/plugins/nvim-lspconfig/config.lua' as well
--
-- for _, file in ipairs(vim.fn.readdir(vim.fn.stdpath "config" .. "/lua/user_functions", [[v:val =~ '\.lua$']])) do
--   require("user_functions." .. file:gsub("%.lua$", ""))
-- end

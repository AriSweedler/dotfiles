vim.o.grepprg = "rg --vimgrep"

local ari = require("ari")

--[[
Error detected while processing /Users/ari.sweedler/.config/nvim/plugin/quickfix.lua:
E5113: Error while calling lua chunk: /Users/ari.sweedler/.config/nvim/lua/ari.lua:8: Expected lua string
stack traceback:
        [C]: in function 'nvim_set_keymap'
        /Users/ari.sweedler/.config/nvim/lua/ari.lua:8: in function 'map'
        /Users/ari.sweedler/.config/nvim/plugin/quickfix.lua:10: in main chunk
--]]
-- vim.api.nvim_get_runtime_file(string.format("queries/%s/%s.scm", vim.o.filetype, 'folds'), true)[0], -- TODO

ari.lua_map("n", "<Leader>ll", { "quickfix", "toggle_llist" })
ari.map("n", "[l", ":lprev<Enter>")
ari.map("n", "]l", ":lnext<Enter>")
ari.map("n", "[L", ":lpfile<Enter>")
ari.map("n", "]L", ":lnfile<Enter>")
ari.map("n", "<Leader>[L", ":lfirst<Enter>")
ari.map("n", "<Leader>]L", ":llast<Enter>")

ari.lua_map("n", "<Leader>qq", { "quickfix", "toggle_qflist" })
ari.map("n", "[q", ":cprev<Enter>")
ari.map("n", "]q", ":cnext<Enter>")
ari.map("n", "[Q", ":cpfile<Enter>")
ari.map("n", "]Q", ":cnfile<Enter>")
ari.map("n", "<Leader>[Q", ":cfirst<Enter>")
ari.map("n", "<Leader>]Q", ":clast<Enter>")

-- Add content to the locationlist
ari.lua_map("n", "<Leader>l+", { "quickfix", "add_curline_llist" })

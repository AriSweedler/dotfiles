vim.pack.add({ "https://github.com/folke/todo-comments.nvim" })

---@type table<string, fun(opts?: table)>
local p = require("snacks").picker
local tc = require("todo-comments")

tc.setup({
	keywords = {
		ERROR = { icon = " ", color = "error" },
		ARISWEEDLER_TODO = { icon = " ", color = "warning" },
		STINKY = { icon = " ", color = "warning" },
	},
	signs = false,
})

vim.keymap.set("n", "]]t", tc.jump_next, { desc = "Todo Comment: Next" })
vim.keymap.set("n", "[[t", tc.jump_prev, { desc = "Todo Comment: Prev" })
vim.keymap.set("n", "<Leader>pt", function()
	p.todo_comments({ dirs = { vim.api.nvim_buf_get_name(0) } })
end, { desc = "Snacks Picker: Todos in buffer" })
vim.keymap.set("n", "<Leader>pT", function()
	p.todo_comments()
end, { desc = "Snacks Picker: All Todos" })

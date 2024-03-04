local ari = require("ari")

-- <Leader>% copies file path to clipboard
for _, fname_modifier in ipairs({ "%", "h", "p", "t", "r" }) do
	local lhs = "<Leader>%" .. fname_modifier
	local rhs = ""
	ari.map("n", lhs, rhs, {
		callback = function()
			vim.fn.setreg("+", vim.fn.expand("%:" .. fname_modifier))
		end,
	})
end

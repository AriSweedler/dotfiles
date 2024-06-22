-- Get 'python' from this filename (which is /Users/ari.sweedler/.config/nvim/snippets/python.lua)
local ft = vim.fn.fnamemodify(vim.fn.expand("<sfile>"), ":t:r")
require("luasnip.session.snippet_collection").clear_snippets(ft)

local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

ls.add_snippets(ft, {
	s(
		"main",
		fmt(
			[[
def main():
	{}
	
if __name__ == "__main__":
	main()
]],
			{ i(0) }
		)
	),
})

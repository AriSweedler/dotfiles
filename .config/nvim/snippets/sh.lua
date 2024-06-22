local file = vim.fn.fnamemodify(vim.fn.expand("<sfile>"), ":t:r")
require("luasnip.session.snippet_collection").clear_snippets(file)

local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmt = require("luasnip.extras.fmt").fmt

ls.add_snippets(file, {
	s("el", fmt("<%= {} %>{}", { i(1), i(0) })),
	s("ei", fmt("<%= if {} do %>{}<% end %>{}", { i(1), i(2), i(0) })),
})

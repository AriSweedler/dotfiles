local M = {}

local luasnip = require("luasnip")
local cmp = require("cmp")

-- Helper function to make the maps look nicer
M.from_sources = function(src)
	local my_sources = {}
	for _, name in ipairs(src) do
		table.insert(my_sources, { name = name })
	end

	return {
		config = {
			sources = my_sources
		}
	}
end

M.snip_right = function()
	if luasnip.expand_or_locally_jumpable() then
		luasnip.expand_or_jump()
	end
end

M.snip_left = function()
	if luasnip.locally_jumpable(-1) then
		luasnip.jump(-1)
	end
end

M.ls_expander = {
	expand = function(args)
		luasnip.lsp_expand(args.body)
	end
}

M.confirm = cmp.mapping.confirm({
	behavior = cmp.ConfirmBehavior.Insert,
	select = true,
})

return M

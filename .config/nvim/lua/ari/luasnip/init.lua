-- Load all my custom snippets
require("luasnip.loaders.from_lua").lazy_load({ paths = { "./lua/ari/luasnip/snippets" } })

-- Create a highlight function using a group prefix
local Theme = require("ari.color.theme")
local ls_hl = Theme.gen("Luasnip", {
	grey = "#262626",
	primary = "#1c3f94",
	secondary = "#005f00",
	tertiary = "#7f2b19",
})

-- Define highlights using the new scaling options
ls_hl("SnippetPassive", { grey = 2 })

ls_hl("InsertPassive", { primary = -1 })
ls_hl("InsertUnvisited", { primary = -2, bold = true })
ls_hl("InsertVisited", { grey = 1 })
ls_hl("InsertActive", { primary = -1 })

ls_hl("ChoicePassive", { secondary = -1 })
ls_hl("ChoiceUnvisited", { secondary = -2, bold = true })
ls_hl("ChoiceVisited", { grey = 1 })
ls_hl("ChoiceActive", { secondary = -1 })

-- Do the actual setup
local ls_types = require("luasnip.util.types")
require("luasnip").config.setup({
	enable_autosnippets = true,
	ext_opts = {
		[ls_types.insertNode] = {
			snippet_passive = {},
			passive = { hl_group = "LuasnipInsertPassive" },
			unvisited = { hl_group = "LuasnipInsertUnvisited" },
			visited = { hl_group = "LuasnipInsertVisited" },
			active = { hl_group = "LuasnipInsertActive" },
		},
		[ls_types.choiceNode] = {
			passive = { hl_group = "LuasnipChoicePassive" },
			unvisited = { hl_group = "LuasnipChoiceUnvisited" },
			visited = { hl_group = "LuasnipChoiceVisited" },
			active = { hl_group = "LuasnipChoiceActive" },
		},
		[ls_types.snippet] = {
			passive = { hl_group = "LuasnipSnippetPassive" },
		}
	}
})

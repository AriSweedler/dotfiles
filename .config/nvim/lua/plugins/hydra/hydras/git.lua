local gitsigns = require("gitsigns")
local preview = require("plugins.hydra.hydras.git_preview")

local function nav(direction)
	preview.close()
	gitsigns.nav_hunk(direction, { wrap = true })
end

local heads = {
	{
		"n",
		function() nav("next") end,
		{ desc = "Next hunk" },
	},
	{
		"N",
		function() nav("prev") end,
		{ desc = "Prev hunk" },
	},
	{
		"s",
		function()
			preview.close()
			gitsigns.stage_hunk()
		end,
		{ desc = "Stage hunk" },
	},
	{
		"r",
		function()
			preview.close()
			gitsigns.reset_hunk()
		end,
		{ desc = "Reset hunk" },
	},
}

-- Appended after `heads` so the closure can reference it as an upvalue
table.insert(heads, {
	"p",
	function() preview.inject_heads(heads) end,
	{ desc = "Preview hunk" },
})

return {
	name = "Git mode",
	mode = "n",
	invoke_on_body = true,
	body = "<Leader>gg",
	config = {
		-- pink means:
		-- 1) default key handler does NOT exit the hydra
		-- 2) foreign keys do NOT exit the hydra (need q/<Esc>)
		color = "pink",
	},
	heads = heads,
}

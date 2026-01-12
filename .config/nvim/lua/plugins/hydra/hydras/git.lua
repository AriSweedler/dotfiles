local hydra_config = {
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
	heads = {
		-- n and p next and prev hunks
		{
			"n",
			function()
				require("gitsigns").nav_hunk("next", { wrap = true })
			end,
			{ desc = "Next hunk" },
		},
		{
			"p",
			function()
				require("gitsigns").nav_hunk("prev", { wrap = true })
			end,
			{ desc = "Prev hunk" },
		},
		{ -- 'N' is a synonym for 'p'
			"N",
			function()
				require("gitsigns").nav_hunk("prev", { wrap = true })
			end,
			{ desc = "Prev hunk" },
		},
		{
			"p",
			function()
				require("gitsigns").preview_hunk()
			end,
			{ desc = "Preview hunk" },
		},
		{
			"s",
			function()
				require("gitsigns").stage_hunk()
			end,
			{ desc = "Stage hunk" },
		},
		{
			"r",
			function()
				require("gitsigns").reset_hunk()
			end,
			{ desc = "Reset hunk" },
		},
	},
}

return hydra_config

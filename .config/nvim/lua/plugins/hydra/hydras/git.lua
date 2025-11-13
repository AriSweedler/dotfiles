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

		-- P for preview
		{
			"P",
			function()
				require("gitsigns").preview_hunk()
			end,
			{ desc = "Preview hunk" },
		},

		-- S for stage. U for undo. R for reset
		-- Capitalized letters imply changing stage
		{
			"S",
			function()
				require("gitsigns").stage_hunk()
			end,
			{ desc = "Stage hunk" },
		},
		{
			"R",
			function()
				require("gitsigns").reset_hunk()
			end,
			{ desc = "Reset hunk" },
		},
	},
}

return hydra_config

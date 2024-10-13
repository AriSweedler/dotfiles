local M = {}

local Ize = require("ari.color.ize")

--- Creates a highlight function for a given group prefix.
-- @param group_prefix String: The prefix for the highlight group.
-- @return Function: A function that creates highlights with the specified prefix.
M.gen = function(group_prefix, opts)
	opts = opts or {}
	opts.grey = opts.grey or "#888888"          -- Default grey
	opts.primary = opts.primary or "#880000"    -- Default reddish
	opts.secondary = opts.secondary or "#008800" -- Default bluish
	opts.tertiary = opts.tertiary or "#000088"  -- Default greenish

	local function generate_hl(group_suffix, hl_opts)
		local group = group_prefix .. group_suffix

		-- Initialize color with nil
		local color = nil

		-- Process color adjustments
		if hl_opts.grey then
			color = Ize.greyscale(opts.grey, hl_opts.grey)
		elseif hl_opts.primary then
			color = Ize.colorize(opts.primary, hl_opts.primary)
		elseif hl_opts.secondary then
			color = Ize.colorize(opts.secondary, hl_opts.secondary)
		elseif hl_opts.tertiary then
			color = Ize.colorize(opts.tertiary, hl_opts.tertiary)
		end

		-- Prepare highlight options
		local highlight_opts = {}
		if color then
			highlight_opts.bg = color:to_hex()
		end

		-- Handle additional options
		if hl_opts.bold then
			highlight_opts.bold = true
		end
		if hl_opts.fg then
			highlight_opts.fg = hl_opts.fg
		end

		-- Set the highlight group
		vim.api.nvim_set_hl(0, group, highlight_opts)
	end

	return generate_hl
end

function M.experiment()
	local Color = require("ari.color")
	local colors = {
		-- Greens
		"#008000", -- Original green
		"#006400", -- Darker green
		"#007d00", -- Slightly lighter green
		"#00b300", -- Bright green
		"#5cb85c", -- Pastel green
		"#80e0a0", -- Soft mint green
		"#66cdaa", -- Medium aqua green
		"#009933", -- Vivid green
		"#4caf50", -- Standard green
		"#3cb371", -- Medium sea green

		-- Purples
		"#800080", -- Original purple
		"#7a0073", -- Darker purple
		"#9b007f", -- Lighter purple
		"#8a007f", -- Balanced purple
		"#a060a0", -- Pastel purple
		"#9370db", -- Medium purple
		"#6a5acd", -- Slate blue
		"#663399", -- Rebecca purple
		"#8a2be2", -- Blue violet
		"#d8bfd8", -- Thistle

		-- Oranges
		"#ff8c00", -- Dark orange
		"#ffa500", -- Original orange
		"#ff7f50", -- Coral
		"#ff6347", -- Tomato
		"#ff4500", -- Orange red
		"#ffb347", -- Light orange
		"#ffcc00", -- Vivid yellow-orange
		"#ffd700", -- Gold
		"#f0e68c", -- Khaki
		"#ffe4b5", -- Blanched almond
	}

	local all_adjusted_colors = {}

	for _, hex in ipairs(colors) do
		local color_obj = Color:new(hex)
		if color_obj then
			local gamut_colors = Ize.gamut(color_obj)

			-- Append the adjusted colors to the main table
			for _, color_info in ipairs(gamut_colors) do
				table.insert(all_adjusted_colors, color_info)
			end
		end
	end

	-- Display all adjusted colors in a new buffer
	Color:display(all_adjusted_colors)
end

function M.gen_test(_, opts)
	opts = opts or {}
	opts.grey = opts.grey or "#888888"          -- Default grey
	opts.primary = opts.primary or "#880000"    -- Default reddish
	opts.secondary = opts.secondary or "#008800" -- Default bluish
	opts.tertiary = opts.tertiary or "#000088"  -- Default greenish

	local all_adjusted_colors = {}

	-- Define the colors to be adjusted
	local color_adjustments = { opts.primary, opts.secondary, opts.tertiary }
	local grey_adjustments = { opts.grey }

	local adjustments = { -4, -3, -2, -1, 0, 1, 2, 3, 4 }

	-- Handle greyscale adjustments
	local Color = require("ari.color")

	for _, grey_hex in ipairs(grey_adjustments) do
		local grey_color_obj = Color:new(grey_hex)

		for _, adjustment in ipairs(adjustments) do
			local adjusted_grey = Ize.greyscale(grey_color_obj:to_hex(), adjustment)
			local gtext = grey_color_obj:format_adjustment(adjustment, adjusted_grey, "Greyscale")
			table.insert(all_adjusted_colors, gtext)
		end
	end

	-- Handle color adjustments
	for _, color_hex in ipairs(color_adjustments) do
		local color_obj = Color:new(color_hex)

		for _, adjustment in ipairs(adjustments) do
			local adjusted_color = Ize.colorize(color_obj:to_hex(), adjustment)
			local ctext = color_obj:format_adjustment(adjustment, adjusted_color, "Colorize")
			table.insert(all_adjusted_colors, ctext)
		end
	end

	-- Display all adjusted colors in a new buffer
	Color:display(all_adjusted_colors)
end

return M

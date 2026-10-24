local Color = require("ari.color")

local Ize = {}

--- Creates a color adjustment function based on the mode.
-- @param mode String: The mode for adjustment ("greyscale" or "colorize").
-- @return Function: A new function that adjusts a color.
local function create_adjustment_function(mode)
	local adjustment_map = {
		greyscale = function(color, adjustment)
			color:adjust_grey(adjustment)
		end,
		colorize = function(color, adjustment)
			color:adjust_color(adjustment)
		end
	}

	return function(hex, adjustment)
		local color = Color:new(hex)
		if not color then return nil end

		if adjustment_map[mode] then
			adjustment_map[mode](color, adjustment)
		else
			vim.api.nvim_err_writeln("Invalid mode: " .. mode)
			return nil
		end

		return color
	end
end

--- Displays adjustments for a single Color object with specified adjustments for greyscale and colorized versions.
-- @param color Color: The Color object to process.
-- @return Table: An array of adjusted colors.
function Ize.gamut(color)
	local adjustments = { -4, -3, -2, -1, 0, 1, 2, 3, 4 }
	local adjusted_colors = {}
	local greyscale_results = {}
	local colorize_results = {}

	for _, adjustment in ipairs(adjustments) do
		local adjusted_grey = Ize.greyscale(color:to_hex(), adjustment)
		local gtext = color:format_adjustment(adjustment, adjusted_grey, "Greyscale")
		table.insert(greyscale_results, gtext)

		local adjusted_color = Ize.colorize(color:to_hex(), adjustment)
		local ctext = color:format_adjustment(adjustment, adjusted_color, "Colorize")
		table.insert(colorize_results, ctext)
	end

	-- Combine the results
	vim.list_extend(adjusted_colors, greyscale_results)
	vim.list_extend(adjusted_colors, colorize_results)

	return adjusted_colors
end

--- Displays adjustments for a single color specified by a hex string.
-- @param hex String: The hex color string to display adjustments for.
function Ize.display_gamut(hex)
	local seed_color = Color:new(hex)
	if not seed_color then
		vim.api.nvim_err_writeln("Invalid seed_color: " .. hex)
		return
	end

	Color:display(Ize.gamut(seed_color))
end

-- Set greyscaler and colorizer functions using the higher-order function
Ize.greyscale = create_adjustment_function("greyscale")
Ize.colorize = create_adjustment_function("colorize")

return Ize

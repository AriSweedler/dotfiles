local Color = {}
Color.__index = Color

local function clamp(value)
	return math.max(0, math.min(255, value))
end

--- Creates a new Color object from a hex color string.
-- @param hex String: The hex color string (e.g., "#RRGGBB").
-- @return Color: A new Color object or nil if the hex string is invalid.
function Color:new(hex)
	if hex:sub(1, 1) ~= "#" then
		vim.api.nvim_err_writeln("Invalid hex color string: " .. hex .. ". It must start with '#'.")
		return nil
	end
	local r = tonumber(hex:sub(2, 3), 16)
	local g = tonumber(hex:sub(4, 5), 16)
	local b = tonumber(hex:sub(6, 7), 16)

	-- Success
	if r and g and b then
		return setmetatable({ r = clamp(r), g = clamp(g), b = clamp(b) }, self)
	end

	-- Failure
	vim.api.nvim_err_writeln("Invalid hex color string: " .. hex .. ". Please ensure it is in the format '#RRGGBB'.")
	return nil
end

--- Converts the Color object to a hex color string.
-- @return String: The hex color string representation of the color.
function Color:to_hex()
	return string.format("#%02x%02x%02x", self.r, self.g, self.b)
end

--- Checks if the color is a shade of grey.
-- @return Boolean: True if the color is grey, false otherwise.
function Color:is_grey()
	return self.r == self.g and self.g == self.b
end

--- Adjusts the RGB color to make it more pastel or darker.
-- A weight of 0 means no change, while a weight of 4 results in pure white.
-- A weight of -4 results in darker
-- @param weight Number: The amount to adjust the color (from -4 to 4).
function Color:adjust_color(weight)
	-- Clamp weight between -4 and 4
	weight = math.max(-4, math.min(weight, 4))

	if weight > 0 then
		-- Blend towards white
		local factor = weight / 4 -- Normalize to 0 to 1
		self.r = math.min(self.r * (1 - factor) + 255 * factor, 255)
		self.g = math.min(self.g * (1 - factor) + 255 * factor, 255)
		self.b = math.min(self.b * (1 - factor) + 255 * factor, 255)
		return
	end

	-- Darkening is more complicated - we don't want black - it's not interesting
	-- Find the brightest channel
	local min_threshold = 50
	local max_color = math.max(self.r, self.g, self.b)
	local rmax = self.r == max_color
	local bmax = self.b == max_color
	local gmax = self.g == max_color

	-- Blend towards black
	local factor = (1 - (-weight / 4))
	self.r = clamp(self.r * factor)
	self.g = clamp(self.g * factor)
	self.b = clamp(self.b * factor)

	-- lighten the former brightest channel (Don't lose the fundamental color)
	if rmax then
		self.r = math.max(self.r, min_threshold)
	elseif gmax then
		self.g = math.max(self.g, min_threshold)
	elseif bmax then
		self.b = math.max(self.b, min_threshold)
	end
end

--- Adjusts the gray color to make it lighter or darker.
-- The function modifies the color components to be equal, resulting in a shade of gray.
-- It adjusts the gray value by a specified amount, clamping the results.
-- @param adjustment Number: The amount to adjust the color towards gray (+ or -).
function Color:adjust_grey(adjustment)
	if not self:is_grey() then
		vim.api.nvim_err_writeln("Warning: Color is not gray; adjustment will be applied to RGB values.")
	end
	local gray = self.r

	gray = clamp(gray + adjustment * 20) -- Adjust by 20 points for each + or -
	self.r = gray
	self.g = gray
	self.b = gray
end

--- Formats the adjustment result for display.
-- @param adjustment Number: The adjustment value applied.
-- @param adjusted_color Color: The adjusted Color object.
-- @param mode String: The mode for adjustment ("Greyscale" or "Colorize").
-- @return String: The formatted adjustment string.
function Color:format_adjustment(adjustment, adjusted_color, mode)
	return string.format("%-10s(%2d): %s", mode, adjustment, adjusted_color:to_hex())
end

--- Displays an array of colors in a new buffer.
-- It opens a new buffer and for each color in the array, it writes the color info,
-- sets a local highlight for each line, and highlights the text using extmarks.
-- @param colors Table: An array of formatted color strings to display.
function Color:display(colors)
	local buf = vim.api.nvim_create_buf(false, true) -- Create a new scratch buffer
	vim.api.nvim_open_win(buf, true, { relative = 'editor', width = 40, height = #colors, row = 1, col = 1 })

	for i, color_info in ipairs(colors) do
		local line = string.format("%s", color_info) -- Directly use the formatted string from gamut
		vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { line })

		-- Extract the hex color code from the color_info string
		local hex_color = color_info:match("(%#%x%x%x%x%x%x)$") or "#000000" -- Default to black if not found

		-- Define the highlight group name
		local highlight_group = string.format("MyHighlight%d", i)

		-- Create a local highlight group with the hex color as the background
		vim.api.nvim_set_hl(0, highlight_group, { bg = hex_color })

		-- Apply the highlight to the line
		vim.api.nvim_buf_add_highlight(buf, -1, highlight_group, i - 1, 0, -1) -- Highlight the line
	end
end

return Color

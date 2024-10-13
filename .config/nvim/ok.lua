require('plenary.reload').reload_module('ari.color')
require('plenary.reload').reload_module('ari.color.ize')
require('plenary.reload').reload_module('ari.color.theme')

-- Global counter to track the current theme index
if not vim.g.theme_index then
	vim.g.theme_index = 1
end

-- Define a new table of themes with unique color combinations
local themes = {
	{
		grey = "#262626",
		primary = "#1c3f94", -- Darker blue
		secondary = "#005f00", -- Dark green
		tertiary = "#b86a00" -- Dark orange
	},
	{
		grey = "#262626",
		primary = "#007f7f", -- Teal
		secondary = "#4c9919", -- Bright green
		tertiary = "#ffcc00" -- Bright yellow
	},
	{
		grey = "#262626",
		primary = "#ff5733", -- Bright red
		secondary = "#8e44ad", -- Purple
		tertiary = "#3498db" -- Light blue
	},
	{
		grey = "#262626",
		primary = "#2ecc71", -- Green
		secondary = "#e74c3c", -- Red
		tertiary = "#f1c40f" -- Yellow
	},
	{
		grey = "#262626",
		primary = "#d35400", -- Orange
		secondary = "#2980b9", -- Blue
		tertiary = "#c0392b" -- Dark red
	},
	{
		grey = "#262626",
		primary = "#e67e22", -- Carrot orange
		secondary = "#16a085", -- Dark teal
		tertiary = "#f39c12" -- Sunflower
	},
	{
		grey = "#262626",
		primary = "#9b59b6", -- Amethyst
		secondary = "#34495e", -- Dark gray-blue
		tertiary = "#2c3e50" -- Darker gray
	},
	{
		grey = "#262626",
		primary = "#f1c40f", -- Yellow
		secondary = "#c0392b", -- Dark red
		tertiary = "#27ae60" -- Emerald
	},
	{
		grey = "#262626",
		primary = "#e74c3c", -- Red
		secondary = "#3498db", -- Light blue
		tertiary = "#34495e" -- Dark gray-blue
	},
	{
		grey = "#262626",
		primary = "#8e44ad", -- Purple
		secondary = "#f39c12", -- Sunflower
		tertiary = "#2980b9" -- Blue
	},
	{
		grey = "#262626",
		primary = "#d35400", -- Orange
		secondary = "#1abc9c", -- Turquoise
		tertiary = "#2c3e50" -- Darker gray
	},
	{
		grey = "#262626",
		primary = "#ffcc00", -- Bright yellow
		secondary = "#e67e22", -- Carrot orange
		tertiary = "#9b59b6" -- Amethyst
	},
	{
		grey = "#262626",
		primary = "#34495e", -- Dark gray-blue
		secondary = "#e74c3c", -- Red
		tertiary = "#16a085" -- Dark teal
	},
	{
		grey = "#262626",
		primary = "#f39c12", -- Sunflower
		secondary = "#2ecc71", -- Green
		tertiary = "#1c3f94" -- Darker blue
	},
	{
		grey = "#262626",
		primary = "#2c3e50", -- Darker gray
		secondary = "#2980b9", -- Blue
		tertiary = "#ff5733" -- Bright red
	},
}

local showcase_theme = function()
	-- Close the current color buffer if it exists
	local existing_bufs = vim.api.nvim_list_bufs()
	for _, buf in ipairs(existing_bufs) do
		if vim.api.nvim_buf_get_name(buf):match("color") then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end

	-- Get the current theme
	local current_theme = themes[vim.g.theme_index] or
			{ grey = "#262626", primary = "#262626", secondary = "#262626", tertiary = "#262626" }
	print(vim.inspect(current_theme), vim.g.theme_index)

	-- Generate the theme
	require("ari.color.theme").gen_test("Luasnip", current_theme)

	-- Increment the index for the next theme, looping back to the first if out of bounds
	vim.g.theme_index = vim.g.theme_index + 1
	if vim.g.theme_index > #themes then
		vim.g.theme_index = 1
	end
end

local ls = require("luasnip")

-- Function to print loaded snippets
function print_loaded_snippets()
end

--
local ls = require("luasnip")
local sl = require("luasnip.extras.snippet_list")

-- Map <Leader>Ps to open the snippet list
vim.keymap.set('n', '<Leader>Ps', function()
	-- You can customize options here
	sl.open({
		snip_info = function(snippet)
			return { name = snippet.name }
		end,
	})
end, { noremap = true, silent = true })

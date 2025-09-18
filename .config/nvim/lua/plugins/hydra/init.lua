local HYDRA_PREFIX = "Hydra: "
local REGISTERED_HYDRA_MAPPINGS = {}

--- Safely refresh lualine if it's loaded
--- Only calls lualine.refresh() if lualine is already required to avoid loading it unnecessarily
local function refresh_lualine()
	-- exit early if lualine is not already required
	if package.loaded['lualine'] then
		require('lualine').refresh()
	end
end

--- Validate that hydra config doesn't contain reserved quit keys
--- Throws an error if the config tries to define 'q' or '<Esc>' keys
--- @param hydra_config table The hydra configuration to validate
local function validate_hydra_config(hydra_config)
	for _, head in ipairs(hydra_config.heads) do
		local key = head[1]
		if key == "q" or key == "<Esc>" then
			error("Hydra config cannot contain 'q' or '<Esc>' keys - these are managed by init.lua")
		end
	end
end

--- Inject standard quit keymaps into hydra configuration
--- Adds 'q' (visible in hint) and '<Esc>' (hidden from hint) as exit keys
--- @param hydra_config table The hydra configuration to modify
local function inject_quit_keymaps(hydra_config)
	table.insert(hydra_config.heads, { "q", nil, { exit = true, nowait = true, desc = "Quit" } })
	table.insert(hydra_config.heads, { "<Esc>", nil, { exit = true, nowait = true, desc = false } })
end

--- Inject <Enter> key to enter the mode immediately
--- Updates lualine, prints mode name, and displays keymap menu
--- The <Enter> key is hidden from hints (desc = false)
--- @param hydra_config table The hydra configuration to modify
local function inject_enter_keymap(hydra_config)
	table.insert(hydra_config.heads, {
		"<Enter>",
		function()
			refresh_lualine()
			print(hydra_config.name)
		end,
		{ desc = false }
	})
end

--- Generate custom hint string for better display with colors
--- Creates a formatted hint with hydra name and colored keys using _key_ syntax
--- Strips HYDRA_PREFIX from descriptions for cleaner display
--- @param hydra_config table The hydra configuration containing heads
--- @return string The formatted hint string
local function generate_hint(hydra_config)
	local hint_lines = { hydra_config.name .. ":" }

	for _, head in ipairs(hydra_config.heads) do
		local key, _, opts = head[1], head[2], head[3]
		if opts and opts.desc and opts.desc ~= false then
			-- Strip HYDRA_PREFIX for display
			local desc = opts.desc:gsub("^" .. HYDRA_PREFIX, "")

			-- Use hydra color syntax: _key_ for colored keys
			table.insert(hint_lines, string.format("  _%s_: %s", key, desc))
		end
	end
	return table.concat(hint_lines, "\n")
end

--- Inject HYDRA_PREFIX to all keymap descriptions
--- Adds the global prefix to all descriptions that don't already have it
--- This ensures consistent labeling for external keymap tools
--- @param hydra_config table The hydra configuration to modify
local function inject_hydra_str_in_keymap_descr(hydra_config)
	for _, head in ipairs(hydra_config.heads) do
		local key, func, opts = head[1], head[2], head[3]
		if opts and opts.desc then
			if not opts.desc:match("^" .. HYDRA_PREFIX) then
				opts.desc = HYDRA_PREFIX .. opts.desc
			end
		end
	end
end

--- Configure hydra hint display and inject custom hint
--- Sets up window-type hint with bottom position and rounded border
--- Generates and applies custom hint string for better formatting
--- @param hydra_config table The hydra configuration to modify
local function configure_hydra_hint(hydra_config)
	-- Configure hint display
	if not hydra_config.config then
		hydra_config.config = {}
	end
	hydra_config.config.hint = {
		type = "window",
		position = "bottom",
		offset = 0,
		float_opts = {
			border = "rounded"
		}
	}

	-- Generate and inject custom hint string
	local custom_hint = generate_hint(hydra_config)
	hydra_config.hint = custom_hint
end

--- Wrap on_exit callback to refresh lualine on hydra exit
--- Preserves any existing on_exit callback and adds lualine refresh
--- @param hydra_config table The hydra configuration to modify
--- @param lambda function The function to call on exit (typically refresh_lualine)
local function wrap_on_exit(hydra_config, lambda)
	local original_on_exit = hydra_config.on_exit
	hydra_config.on_exit = function()
		if original_on_exit then
			original_on_exit()
		end
		lambda()
	end
end

--- Load and configure a single hydra config file
--- Loads a hydra config module, applies all transformations, and creates the hydra instance
--- Also registers the hydra mapping information for the reflective display
--- @param file string The file path to load (should be a .lua file in the hydras directory)
local function load_hydra_config_file(file)
	local module = "plugins.hydra.hydras." .. file:match("([^/]+)%.lua$")
	local hydra_config = require(module)
	if not hydra_config then
		return
	end
	-- Collect mapping info
	table.insert(REGISTERED_HYDRA_MAPPINGS, {
		body = hydra_config.body,
		name = hydra_config.name
	})

	validate_hydra_config(hydra_config)
	inject_quit_keymaps(hydra_config)
	inject_enter_keymap(hydra_config)
	inject_hydra_str_in_keymap_descr(hydra_config)
	configure_hydra_hint(hydra_config)
	wrap_on_exit(hydra_config, refresh_lualine)

	require("hydra")(hydra_config)
end

--- Create mapping to show all registered hydra mappings
--- Sets up keymap that displays all available hydra modes and their trigger keys
--- Uses vim.notify to show the information in a notification popup
local function create_hydra_help_mapping(lhs)
	vim.keymap.set('n', lhs, function()
		local lines = { "Available Hydra modes:" }
		for _, mapping in ipairs(REGISTERED_HYDRA_MAPPINGS) do
			table.insert(lines, "  " .. mapping.body .. " -> " .. mapping.name)
		end
		vim.notify(table.concat(lines, "\n"))
	end, { desc = "Show hydra mappings" })
end

local M = {
	"nvimtools/hydra.nvim",
	event = "VeryLazy",
	config = function()
		-- For each file in '$0/../hydras', define a hydra:
		local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
		local hydras = script_dir .. "hydras"
		for _, file in ipairs(vim.fn.glob(hydras .. "/*.lua", true, true)) do
			load_hydra_config_file(file)
		end

		create_hydra_help_mapping('<Leader>??')
	end,
}

return M

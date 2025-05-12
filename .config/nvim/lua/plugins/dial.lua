local function generate_keys()
	local g_prefixes = {
		[""] = "", -- no "g"
		["g"] = "g", -- with "g"
	}

	local key_actions = {
		["<C-a>"] = "increment",
		["<C-x>"] = "decrement",
	}

	local modes = {
		n = "normal",
		v = "visual",
	}

	local keys = {}

	for g_prefix, g_mode_prefix in pairs(g_prefixes) do
		for key, action in pairs(key_actions) do
			for mode, mode_str in pairs(modes) do
				table.insert(keys, {
					g_prefix .. key,
					function()
						require("dial.map").manipulate(action, g_mode_prefix .. mode_str)
					end,
					mode = mode,
					desc = action:sub(1, 1):upper() .. action:sub(2) .. " in " .. g_mode_prefix .. mode_str .. " mode",
				})
			end
		end
	end

	return keys
end

local M = {
	"monaqa/dial.nvim",
	keys = generate_keys(),
	config = function()
		local augend = require("dial.augend")

		require("dial.config").augends:register_group({
			default = {
				augend.semver.alias.semver,
				augend.integer.alias.decimal,
				augend.date.alias["%Y-%m-%d"],
			},
		})
	end,
}

return M

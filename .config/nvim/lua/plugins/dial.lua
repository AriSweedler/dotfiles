--- Create a dial.nvim augend for cycling through constant values.
--- @param elements string[] List of strings to cycle through
--- @param opts? table Options table
--- @param opts.word? boolean Match whole words only (default: true)
--- @param opts.cyclic? boolean Wrap around at ends (default: true)
--- @return table augend The configured augend
local function ari_augend(elements, opts)
	opts = opts or {}
	local augend = require("dial.augend")
	return augend.constant.new({
		elements = elements,
		word = opts.word ~= false,
		cyclic = opts.cyclic ~= false,
	})
end

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
		local default_augends = {
			augend.semver.alias.semver,
			augend.integer.alias.decimal,
			augend.date.alias["%Y-%m-%d"],
			ari_augend({ "❮", "❯" }, { word = false }),
		}
		require("dial.config").augends:register_group({
			default = default_augends,
		})

		local shell_augends = vim.list_extend({
			ari_augend({ "c_green", "c_yellow", "c_red" }),
			ari_augend({ "c_cyan", "c_grey" }),
		}, default_augends)
		require("dial.config").augends:on_filetype({
			zsh = shell_augends,
			sh = shell_augends,
		})
	end,
}

return M

vim.pack.add({
	"https://github.com/nvim-tree/nvim-web-devicons",
	"https://github.com/stevearc/oil.nvim",
})

local desc = "[ari] [lazyload] Oil file browser"
local show_detail = false
local detail_permissions = { "permissions", highlight = "Special" }
local detail_size = { "size", highlight = "Constant" }
local detail_mtime = { "mtime", highlight = "Statement" }
local oil_opts = {
	columns = { "icon" },
	default_file_explorer = true,
	win_options = {
		cursorline = true,
	},
	float = {
		get_win_title = function()
			return " " .. require("oil").get_current_dir()
		end,
		border = "rounded",
	},
	keymaps = {
		["<Esc>"] = {
			"actions.close",
			desc = "Close oil",
			mode = "n",
		},
		["gd"] = {
			function()
				local oil = require("oil")
				show_detail = not show_detail
				if show_detail then
					oil.set_columns({ "icon", detail_permissions, detail_mtime, detail_size })
				else
					oil.set_columns({ "icon" })
				end
			end,
			desc = "Toggle show_detail view",
			mode = "n",
		},
	},
	view_options = {
		show_hidden = true,
		is_always_hidden = function(name, _)
			local always_hidden_files = {
				".git",
				".DS_Store",
				"__pycache__",
			}
			return vim.tbl_contains(always_hidden_files, name)
		end,
	},
}

local double_tap_openers = {
	{ key = "<C-T><C-T>", opt = "tab",        desc = "new tab" },
	{ key = "<C-V><C-V>", opt = "vertical",   desc = "vertical split" },
	{ key = "<C-S><C-S>", opt = "horizontal", desc = "horizontal split" },
}
for _, opener in ipairs(double_tap_openers) do
	oil_opts.keymaps[opener.key] = {
		"actions.select",
		opts = { [opener.opt] = true },
		desc = opener.desc,
	}
end

require("oil").setup(oil_opts)
vim.keymap.set("n", "-", require("oil").toggle_float, { desc = desc })

vim.pack.add({ "https://github.com/nvim-lualine/lualine.nvim" })

local function hydra_mode()
	return require("hydra.statusline").get_name()
end

require("lualine").setup({
	options = {
		theme = "wombat",
		path = 1,
		shorting_target = 40,
		globalstatus = true,
	},
	sections = {
		lualine_a = {
			"mode",
			{
				hydra_mode,
				cond = function()
					return require("hydra.statusline").is_active()
				end,
			},
		},
		lualine_y = {
			"lsp_status",
		},
		lualine_z = {
			"selectioncount",
			"progress",
			"location",
		},
	},
	tabline = {
		lualine_a = { {
			"tabs",
			use_mode_colors = true,
			-- Show custom name if renamed via :LualineRenameTab, otherwise just the number
			mode = 1,
			fmt = function(_, context)
				local name = vim.fn.gettabvar(context.tabnr, "tabname", "")
				return name ~= "" and name or tostring(context.tabnr)
			end,
		} },
		lualine_b = {},
		lualine_c = {},
		lualine_x = {},
		lualine_y = {},
		lualine_z = { { "buffers", mode = 2, use_mode_colors = true } },
	},
})

vim.keymap.set("n", "<Leader>[T", ":LualineRenameTab ", { desc = "Rename tab" })

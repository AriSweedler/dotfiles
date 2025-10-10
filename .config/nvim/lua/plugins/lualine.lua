local function snippet_mode()
	local ls = require("luasnip")
	return ls.in_snippet() and "SNIP" or ""
end

local function hydra_mode()
	return require("hydra.statusline").get_name()
end

local function LSP_list()
	local clients = vim.lsp.get_clients()
	if #clients <= 0 then
		return "No LSP"
	end

	local names = {}
	for _, client in ipairs(clients) do
		table.insert(names, client.name)
	end

	local ans = table.concat(names, ", ")

	return ans
end

local M = {
	"nvim-lualine/lualine.nvim",
	event = "VimEnter",
	opts = {
		options = {
			theme = "wombat",
			path = 1,
			shorting_target = 40,
		},
		sections = {
			lualine_a = {
				"mode",
				snippet_mode,
				{
					hydra_mode,
					cond = function()
						return require("hydra.statusline").is_active()
					end,
				},
			},
			lualine_y = {
				LSP_list,
			},
		},
	},
}

return M

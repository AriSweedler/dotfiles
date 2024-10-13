local function snippet_mode()
	local ls = require("luasnip")
	return ls.in_snippet() and "SNIP" or ""
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

local progress_symbols = {
	status = {
		hl = {
			enabled = "#50FA7B",
			sleep = "#AEB7D0",
			disabled = "#6272A4",
			warning = "#FFB86C",
			unknown = "#FF5555"
		}
	},
	-- require("copilot-lualine").spinners.moon
	spinners = { "🌑 ", "🌒 ", "🌓 ", "🌔 ", "🌕 ", "🌖 ", "🌗 ", "🌘 " },
	spinner_color = "#6272A4"
}

local M = {
	"nvim-lualine/lualine.nvim",
	event = "BufReadPre",
	dependencies = {
		"AndreM222/copilot-lualine",
	},
	opts = {
		options = {
			theme = "wombat",
			path = 1,
		},
		sections = {
			lualine_a = { 'mode', snippet_mode },
			lualine_y = {
				"copilot",
				{ "progress", symbols = progress_symbols },
				LSP_list,
			},
		},
	},
}

return M

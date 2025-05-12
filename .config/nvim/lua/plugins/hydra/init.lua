local M = {
	"nvimtools/hydra.nvim",
	event = "VeryLazy",
	config = function()
		local Hydra = require("hydra")

		-- For each file in this folder, define a hydra from it:
		local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
		local hydras = script_dir .. "hydras"
		for _, file in ipairs(vim.fn.glob(hydras .. "/*.lua", true, true)) do
			local module = "plugins.hydra.hydras." .. file:match("([^/]+)%.lua$")
			local hydra_config = require(module)
			if hydra_config then
				Hydra(hydra_config)
			end
		end
	end,
}

return M

local M = {
	"cuducos/yaml.nvim",
	ft = { "yaml" },
	dependencies = {
		"folke/snacks.nvim",
	},
}

-- Buffer-local keymappings
local bufmap = function(lhs, rhs, desc, opts)
	opts = opts or {}
	opts.buffer = true
	opts.desc = "yaml.nvim: " .. desc
	vim.keymap.set("n", lhs, rhs, opts)
end

local function ftplugin()
	vim.wo.winbar = "%{%v:lua.require'ari.yaml_utils'.get_yaml_key_at_cursor()%}"

	bufmap("I", function()
		vim.cmd("InspectTree")
	end, "Open InspectTree")

	bufmap("Y", function()
		local path = require("ari.yaml_utils").get_yaml_key_at_cursor()
		vim.fn.setreg("+", path)
		vim.notify("Copied YAML path: '" .. path .. "'", vim.log.levels.INFO)
	end, "copy yaml path")
end

function M.init()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "yaml", "yml" },
		callback = ftplugin,
	})
end

return M

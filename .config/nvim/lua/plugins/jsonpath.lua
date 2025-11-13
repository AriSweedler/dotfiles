local M = {
	"phelipetls/jsonpath.nvim",
	ft = "json",
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
	},
	config = function()
		require("jsonpath").setup({
			show_on_winbar = true,
		})
	end,
}

-- Buffer-local keymappings
local bufmap = function(lhs, rhs, desc, opts)
	opts = opts or {}
	opts.buffer = true
	opts.desc = "jsonpath: " .. desc
	vim.keymap.set("n", lhs, rhs, opts)
end


local function ftplugin()
	-- For some reason, the winbar doesn't show proper data until this is run
	bufmap("I", function()
		vim.cmd("InspectTree")
	end, "Open InspectTree (to make winbar work)")

	vim.wo.winbar = "%{%v:lua.require'jsonpath'.get()%}"

	bufmap("Y", function()
		local path = require("jsonpath").get()
		vim.fn.setreg("+", path)
		vim.notify("Copied JSON path: '" .. path .. "'", vim.log.levels.INFO)
	end, "copy json path")
end

function M.init()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "json", "jsonl" },
		callback = ftplugin,
	})
end

return M

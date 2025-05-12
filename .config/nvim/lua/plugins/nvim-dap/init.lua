local M = {
	"mfussenegger/nvim-dap",
	recommended = true,
	desc = "Debugging support. Requires language specific adapters to be configured",
	event = "VeryLazy",
	dependencies = {
		"rcarriga/nvim-dap-ui",
		"nvim-neotest/nvim-nio",
		"theHamsta/nvim-dap-virtual-text",
		"jay-babu/mason-nvim-dap.nvim",
		{
			"miroshQa/debugmaster.nvim",
			config = function()
				local dm = require("debugmaster")
				vim.keymap.set({ "n", "v" }, "<Leader><Leader>d", dm.mode.toggle, { nowait = true })
			end,
		},
	},
	keys = require("plugins.nvim-dap.keys"),
	config = require("plugins.nvim-dap.config"),
}

return M

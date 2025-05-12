---@diagnostic disable: assign-type-mismatch
local function set_icons()
	-- icons is a table where the key is the name of the sign. The value is an
	-- array with the entries
	-- @string icon to use
	-- @string highlight group to use
	-- @string linehl to use
	-- @string numhl to use
	local icons = {
		Breakpoint = { "🛑", "DiagnosticSignError" },
		BreakpointCondition = { "❤️", "DiagnosticSignWarn" },
		BreakpointRejected = { "❌", "DiagnosticSignError" },
		LogPoint = { "💬", "DiagnosticSignInfo" },
		Stopped = { "▶️", "DiagnosticSignHint" },
		Paused = { "⏸️", "DiagnosticSignHint" },
		BreakpointData = { "💬", "DiagnosticSignInfo" },
	}
	for name, sign in pairs(icons) do
		sign = type(sign) == "table" and sign or { sign }
		vim.fn.sign_define("Dap" .. name, {
			text = sign[1] or "⚠️",
			texthl = sign[2] or "DiagnosticInfo",
			linehl = sign[3] or "None",
			numhl = sign[3] or "None",
		})
	end
end

return function()
	-- load mason-nvim-dap here, after all adapters have been setup
	require("mason-nvim-dap").setup({
		ensure_installed = { "delve" },
		handlers = {},
		automatic_installation = true,
	})

	local dap, dapui = require("dap"), require("dapui")

	dapui.setup()

	-- Open dap-ui automatically
	dap.listeners.after.event_initialized["dapui_config"] = function()
		dapui.open()
	end
	dap.listeners.before.event_terminated["dapui_config"] = function()
		dapui.close()
	end
	dap.listeners.before.event_exited["dapui_config"] = function()
		dapui.close()
	end

	vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })

	set_icons()
end

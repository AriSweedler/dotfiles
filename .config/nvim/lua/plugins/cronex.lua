local ns = vim.api.nvim_create_namespace("cronex-virtual-text")
local cronex_enabled = false

local M = {
	'fabridamicelli/cronex.nvim',
	lazy = true,
	keys = {
		{ "\\tc", "<cmd>ToggleCronEx<cr>", desc = "Toggle [C]ron explainer" },
	},
}

M.config = function()
	require("cronex").setup({})
	-- The upstream plugin does not allow us to override the 'explain' function via
	-- 'options to the setup function'. Thus, we must run the following after setup
	-- (which means we must run setup ourselves)
	require("cronex").config.explain = require("ari.cronex").explain_with_virtual_text
end

M.init = function()
	vim.api.nvim_create_user_command("ToggleCronEx", function()
		if not require("ari.cronex").check_cronstrue() then
			vim.notify("Cron Explainer requires cronstrue. Install with: npm install -g cronstrue", vim.log.levels.ERROR)
			return
		end

		vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
		if cronex_enabled then
			require("cronex").disable()
			cronex_enabled = false
			vim.notify("Cron Explainer disabled")
			return
		end

		require("cronex").enable()
		cronex_enabled = true
		vim.notify("Cron Explainer enabled")
	end, { desc = "Cron Explainer: toggle for current buffer" })
end

return M

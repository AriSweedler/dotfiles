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
			vim.notify("[Cron Explainer] requires cronstrue. Install with: npm install -g cronstrue", vim.log.levels.ERROR)
			return
		end

		vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)

		cronex_enabled = not cronex_enabled
		vim.notify(string.format("[Cron Explainer] plugin %s", cronex_enabled and "enabled" or "disabled"))
		if cronex_enabled then
			require("cronex").enable()
		else
			require("cronex").disable()
		end
	end, { desc = "[Cron Explainer] toggle for current buffer" })

	-- Auto-enable for file types that commonly have cron expressions
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "yaml", "terraform", "conf", "config", "typescriptreact" },
		callback = function()
			vim.cmd("ToggleCronEx")
		end,
		desc = "Auto-enable Cron Explainer for config files",
	})
end

return M

-- lazy.nvim
local M = {
	"folke/noice.nvim",
	dependencies = {
		"MunifTanjim/nui.nvim",
		"rcarriga/nvim-notify",
	},
	-- TODO: Disabling for now because I don't prefer it - but I wanna check it
	-- out more in the future...
	-- event = "VeryLazy",
	opts = {
		-- add any options here
	},
	config = function(_, opts)
		require("noice").setup(opts)

		-- Normally, I have this keymap clear highlights. But I really just want it
		-- to mean "distraction level: LOW". So it can clear highlights AND ALSO
		-- notifications.
		vim.keymap.set({ "n", "i", "v" }, "<C-_>", function()
			require("noice").cmd("dismiss")
			vim.cmd("nohlsearch")
		end)

		-- If I ever wanna take the output of a command (or iterate on it)
		vim.keymap.set("c", "<Leader><Enter>", function()
			require("noice").redirect(vim.fn.getcmdline())
		end, { desc = "Redirect Cmdline to tmp floating buffer" })
	end,
}

-- TODO: Get rid of flashy cursor (don't animate notifications falling off)

return M

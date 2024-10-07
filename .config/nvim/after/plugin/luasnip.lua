local ls = require("luasnip")

-- Function to open LuaSnip log in a new tab
local function open_luasnip_log()
	local log_location = ls.log.log_location() .. "/luasnip.log"
	if log_location then
		vim.cmd("tabnew " .. log_location)
	else
		print("LuaSnip log location not found.")
	end
end

-- Create the user command
vim.api.nvim_create_user_command("LogLuasnip", open_luasnip_log, {})

-- Set loglevel
-- ls.log.set_loglevel("debug")

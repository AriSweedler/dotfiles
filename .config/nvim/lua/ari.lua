local M = {}

function M.buf_map(mode, lhs, rhs, opts_override)
	local opts = { noremap = true, silent = true }
	if opts_override then
		opts = vim.tbl_extend("force", opts, opts_override)
	end
	vim.api.nvim_buf_set_keymap(0, mode, lhs, rhs, opts)
end

function M.map(mode, lhs, rhs, opts_override)
	local opts = { noremap = true, silent = true }
	if opts_override then
		opts = vim.tbl_extend("force", opts, opts_override)
	end
	vim.api.nvim_set_keymap(mode, lhs, rhs, opts)
end

local function convert_and_join_args(args)
	if not args then
		return ""
	end

	local args_str = ""
	for i, v in ipairs(args) do
		args_str = args_str .. tostring(v)
		if i ~= #args then
			args_str = args_str .. ", "
		end
	end

	return args_str
end

--[[
-- You need to expose lua functions to vim through 'require'd modules. Otherwise
-- we cannot see the lua scripts
--
-- With this function, you can make a mapping to invoke a lua function
--
--     ari.lua_map('n', lhs, {"quickfix", "toggle_llist", "my_arg"})
--
-- fxn defined in './lua/quickfix.lua' named 'toggle_llist' & given '"my_arg"'
--]]
function M.lua_map(mode, lhs, rfa, opts)
	local requirement, fxn, args = rfa[1], rfa[2], rfa[3]
	local args_str = convert_and_join_args(args)
	local rhs = '<Cmd>lua require("' .. requirement .. '").' .. fxn .. "(" .. args_str .. ")<CR>"
	M.map(mode, lhs, rhs, opts)
end

return M

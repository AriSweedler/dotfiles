-- Module for creating custom Vim operators
local M = {}

---------------------------------------------------------------------------
-- General-purpose operator function wrapper
---------------------------------------------------------------------------
local function make_operator_func(fn)
	return function(_type)
		local bufnr = 0
		local srow = vim.fn.getpos("'[")[2]
		local erow = vim.fn.getpos("']")[2]
		if srow == 0 or erow == 0 then return end
		local start0   = math.min(srow, erow) - 1
		local end_excl = math.max(srow, erow)
		fn(bufnr, start0, end_excl)
	end
end

---@class CreateOperatorOpts
---@field fn fun(bufnr: number, start0: number, end_excl: number) Function to call on the region
---@field name string Unique global name for the operator function
---@field lhs string Keymap left-hand side (e.g., "<Leader>c")
---@field desc? string Description for the keymap
---@field mode? string|string[] Modes to map (default: {"n", "x"})
---@field buffer? boolean Buffer-local mapping (default: true)

--- Create operator keymaps for any Lua function.
--- Registers the function globally and creates keymaps for operator-pending,
--- visual mode, and a "this line" convenience binding.
---@param opts CreateOperatorOpts
function M.create_operator(opts)
	opts = opts or {}

	-- Required parameters
	if not opts.fn then error("create_operator requires 'fn' parameter") end
	---@type fun(bufnr: number, start0: number, end_excl: number)
	local _ = opts.fn
	if not opts.name then error("create_operator requires 'name' parameter") end
	if not opts.lhs then error("create_operator requires 'lhs' parameter") end
	if not opts.desc then error("create_operator requires 'desc' parameter") end

	-- Register the operator function globally with the given name
	_G[opts.name] = make_operator_func(opts.fn)
	local opfunc_name = "v:lua._G." .. opts.name

	-- Optional parameters
	local modes = opts.mode or { "n", "x" }
	if type(modes) == "string" then modes = { modes } end

	local base_desc = "Operator: " .. opts.desc
	local buffer = (opts.buffer ~= nil) and opts.buffer or true

	-- Create operator keymaps for n and x modes
	for _, m in ipairs(modes) do
		local desc = base_desc .. (m == "x" and " [visual]" or " (operator)")
		vim.keymap.set(m, opts.lhs, function()
			vim.go.operatorfunc = opfunc_name
			return "g@"
		end, { expr = true, buffer = buffer, desc = desc })
	end

	-- Normal mode "this line" helper (with <CR>)
	for _, m in ipairs(modes) do
		if m == "n" then
			vim.keymap.set("n", opts.lhs .. opts.lhs, function()
				vim.go.operatorfunc = opfunc_name
				return "g@_"
			end, { expr = true, buffer = buffer, desc = base_desc .. " (this line)" })
			break
		end
	end
end

return M

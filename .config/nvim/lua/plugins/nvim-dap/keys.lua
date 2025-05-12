---@param desc string
---@param opts table|nil
---| {capitalize: boolean, keystone_char_index: integer}
---@return string
local function ddesc(desc, opts)
	-- Massage args
	opts = opts or {}
	local keystone_char_index = opts.keystone_char_index or 1

	-- Find the 3 components of the string
	local prefix = desc:sub(1, keystone_char_index - 1)
	local keystone_char = desc:sub(keystone_char_index, keystone_char_index)
	local rest_of_desc = desc:sub(keystone_char_index + 1)

	-- Transform data if opts request it
	if opts.capitalize then
		keystone_char = keystone_char:upper()
	end

	-- Produce the string
	local ans = "[d]ebug " .. prefix .. "[" .. keystone_char .. "]" .. rest_of_desc
	return ans
end

return {
	-- Start and stop
	{
		"<Leader>dS",
		function()
			require("dap").continue()
		end,
		desc = ddesc("start or continue", { capitalize = true }),
	},
	{
		"<Leader>dT",
		function()
			require("dap").terminate()
			require("dapui").close()
		end,
		desc = ddesc("terminate or stop. Disconnect and close", { capitalize = true }),
	},
	{
		"<Leader>dL",
		function()
			require("dap").run_last()
		end,
		desc = ddesc("run last", {
			capitalize = true,
			keystone_char_index = 5,
		}),
	},
	{
		"<Leader>dP",
		function()
			require("dap").pause()
		end,
		desc = ddesc("pause", {
			capitalize = true,
		}),
	},

	-- Run to cursor
	{
		"<Leader>dC",
		function()
			require("dap").run_to_cursor()
		end,
		desc = ddesc("run to cursor", {
			capitalize = true,
			keystone_char_index = 8,
		}),
	},

	-- Step (continue, into, out, over)
	{
		"<Leader>dsc",
		function()
			require("dap").continue()
		end,
		desc = ddesc("continue or start"),
	},
	{
		"<Leader>dsi",
		function()
			require("dap").step_into()
		end,
		desc = ddesc("step into", {
			keystone_char_index = 6,
		}),
	},
	{
		"<Leader>dso",
		function()
			require("dap").step_out()
		end,
		desc = ddesc("step out", {
			keystone_char_index = 6,
		}),
	},
	{
		"<Leader>dsO",
		function()
			require("dap").step_over()
		end,
		desc = ddesc("step over", {
			keystone_char_index = 6,
			capitalize = true,
		}),
	},

	-- Stacktrace: up and down
	{
		"<Leader>dj",
		function()
			require("dap").down()
		end,
		desc = ddesc("j is down"),
	},
	{
		"<Leader>dk",
		function()
			require("dap").up()
		end,
		desc = ddesc("k is up"),
	},

	-- hover
	{
		"<Leader>dK",
		function()
			require("dap.ui.widgets").hover()
		end,
		desc = ddesc("widget hover variables"),
	},

	-- ui toggle
	{
		"<Leader>du",
		function()
			require("dapui").toggle()
		end,
		desc = ddesc("ui"),
	},
	{
		"<Leader>dr",
		function()
			require("dap").repl.toggle()
		end,
		desc = ddesc("toggle repl", {
			keystone_char_index = 8,
		}),
	},

	-- Breakpoints
	{
		"<Leader>db",
		function()
			require("dap").toggle_breakpoint()
		end,
		desc = ddesc("breakpoint"),
	},
	{
		"<Leader>dB",
		function()
			require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
		end,
		desc = ddesc("breakpoint condition", { capitalize = true }),
	},
	{
		"[db",
		function()
			require("plugins.nvim-dap.breakpoint").jump("prev")
		end,
		desc = "jump to prev breakpoint",
	},
	{
		"]db",
		function()
			require("plugins.nvim-dap.breakpoint").jump("next")
		end,
		desc = "jump to next breakpoint",
	},

	-- Help
	{
		"<Leader>d?",
		function()
			vim.cmd("map <Leader>d")
		end,
		desc = ddesc("? - help list all keymaps"),
	},
}

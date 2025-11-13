local M = {
	"yochem/jq-playground.nvim",
	cmd = "JqPlayground",
	opts = {
		disable_default_keymap = false,
	},
}

-- Escape single quotes for a single-quoted shell string:
-- ' -> '"'"'
local function xq_escape(str)
	return str:gsub("'", "'\"'\"'")
end

-- Buffer-local keymappings
local bufmap = function(lhs, rhs, desc, opts)
	opts = opts or {}
	opts.buffer = true
	opts.desc = "JqPlayground: " .. desc
	local mode = opts.mode or 'n'
	opts.mode = nil
	vim.keymap.set(mode, lhs, rhs, opts)
end

local function ftplugin_xq()
	bufmap("Y", function()
		-- Grab full buffer
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local content = table.concat(lines, "\n")
		local escaped = xq_escape(content)

		-- Build command and copy to clipboard
		local cmd = vim.o.filetype .. " '" .. escaped .. "' " .. vim.api.nvim_buf_get_name(vim.b.jqplayground_inputbuf)
		vim.fn.setreg("+", cmd)

		vim.notify("Copied " .. vim.o.filetype .. " command: " .. cmd, vim.log.levels.INFO)
	end, "Copy buffer into " .. vim.o.filetype .. " command")

	-- We don't want to save this buffer
	bufmap("<C-f>", "<Plug>(JqPlaygroundRunQuery)", "run query", { mode = { "i", "n" } })
	vim.bo.buftype = "nofile"
	vim.bo.swapfile = false
	vim.bo.bufhidden = "hide"
end

local function get_xq_query()
	local filetype = vim.bo.filetype

	if filetype == "json" or filetype == "jsonl" then
		return require("jsonpath").get()
	elseif filetype == "yaml" or filetype == "yml" then
		return require("yaml_nvim").get_yaml_key()
	else
		vim.notify("Unsupported filetype: " .. filetype, vim.log.levels.ERROR)
		return nil
	end
end

local function jqPlaygroundOpenSeeded()
	-- read the jq/yq path that we are on
	local xq_query = get_xq_query()
	xq_query = "." .. (xq_query or '')

	vim.cmd.JqPlayground()

	-- Insert the yq/jq path as the seed of our query
	vim.schedule(function()
		vim.api.nvim_put({ xq_query }, "c", false, true)
	end)
end

local function ftplugin_jqplayground_init()
	bufmap("Q", jqPlaygroundOpenSeeded, "Open with file path")
	bufmap("<Leader>Q", vim.cmd.JqPlayground, "Open")
end

function M.init()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "jq", "yq" },
		callback = ftplugin_xq,
	})
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "json", "jsonl", "yaml" },
		callback = ftplugin_jqplayground_init,
	})
end

return M

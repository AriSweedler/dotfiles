local M = {
	"yochem/jq-playground.nvim",
	cmd = "JqPlayground",
	opts = {
		disable_default_keymap = false,
	},
}

-- Escape single quotes for a single-quoted shell string:
-- ' -> '"'"'
local function jq_escape(str)
	return str:gsub("'", "'\"'\"'")
end

-- Buffer-local keymappings
local bufmap = function(lhs, rhs, desc, opts)
	opts = opts or {}
	opts.buffer = true
	opts.desc = "JqPlayground: " .. desc
	vim.keymap.set("n", lhs, rhs, opts)
end

local function ftplugin_jq()
	-- TODO: Know what file we are attached to...

	bufmap("Y", function()
		-- Grab full buffer
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local content = table.concat(lines, "\n")
		local escaped = jq_escape(content)

		-- Build command and copy to clipboard
		local cmd = "jq '" .. escaped .. "'"
		vim.fn.setreg("+", cmd)

		vim.notify("Copied jq command: " .. cmd, vim.log.levels.INFO)
	end, "Copy buffer into jq command")

	-- We don't want to save this buffer
	bufmap("<C-f>", "<Plug>(JqPlaygroundRunQuery)", "run query")
	vim.bo.buftype = "nofile"
	vim.bo.swapfile = false
	vim.bo.bufhidden = "hide"
end

local function ftplugin_json()
	bufmap("Q", vim.cmd.JqPlayground, "Open")
end

function M.init()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "jq",
		callback = ftplugin_jq,
	})
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "json",
		callback = ftplugin_json,
	})
end

return M

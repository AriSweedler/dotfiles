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

local function jqPlaygroundClose()
	local playground_wins = vim.t.jqplayground_wins
	if not playground_wins then
		vim.notify("No active playground in this tab", vim.log.levels.WARN)
		return
	end

	-- Close both windows if they're valid
	if playground_wins.query and vim.api.nvim_win_is_valid(playground_wins.query) then
		vim.api.nvim_win_close(playground_wins.query, false)
	end
	if playground_wins.output and vim.api.nvim_win_is_valid(playground_wins.output) then
		vim.api.nvim_win_close(playground_wins.output, false)
	end

	-- Clear the tab-local variable
	vim.t.jqplayground_wins = nil
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

	bufmap("q", jqPlaygroundClose, "Close playground")

	-- We don't want to save this buffer
	bufmap("<C-f>", "<Plug>(JqPlaygroundRunQuery)", "run query", { mode = { "i", "n" } })
	vim.bo.buftype = "nofile"
	vim.bo.swapfile = false
	vim.bo.bufhidden = "hide"
end

local function get_xq_query()
	local filetype = vim.bo.filetype

	local ans = ''
	if filetype == "json" or filetype == "jsonl" then
		ans = require("jsonpath").get()
	elseif filetype == "yaml" or filetype == "yml" then
		ans = require("ari.yaml_utils").get_yaml_key_at_cursor()
	else
		vim.notify("Unsupported filetype: " .. filetype, vim.log.levels.ERROR)
		ans = ''
	end

	local function ensure_dot_prefix(s)
		if not s or s == '' or s == 'null' then
			return '.'
		end
		return s:match("^%.") and s or ("." .. s)
	end
	return ensure_dot_prefix(ans)
end

local function jqPlaygroundOpenSeeded()
	local xq_query = get_xq_query()

	-- Check if there's already an active playground in this tab
	local playground_wins = vim.t.jqplayground_wins
	if playground_wins then
		-- Check if the windows are still valid
		local query_win_valid = playground_wins.query and vim.api.nvim_win_is_valid(playground_wins.query)
		local output_win_valid = playground_wins.output and vim.api.nvim_win_is_valid(playground_wins.output)

		if query_win_valid then
			-- Reuse existing playground
			vim.api.nvim_set_current_win(playground_wins.query)
			vim.schedule(function()
				vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
				vim.api.nvim_put({ xq_query }, "c", false, true)
			end)
			return
		end
	end

	-- Track windows before creating playground
	local wins_before = vim.api.nvim_tabpage_list_wins(0)
	local wins_before_set = {}
	for _, win in ipairs(wins_before) do
		wins_before_set[win] = true
	end

	-- No existing playground, create new one
	vim.cmd.JqPlayground()

	-- Store the playground windows in tab-local variable
	vim.schedule(function()
		local query_win = vim.api.nvim_get_current_win()
		local query_buf = vim.api.nvim_get_current_buf()

		-- Find the output window (one of the new windows created by JqPlayground)
		local wins_after = vim.api.nvim_tabpage_list_wins(0)
		local output_win = nil
		for _, win in ipairs(wins_after) do
			-- This is a new window created by JqPlayground
			if not wins_before_set[win] and win ~= query_win then
				output_win = win
				break
			end
		end

		vim.t.jqplayground_wins = {
			query = query_win,
			output = output_win,
		}

		-- Insert the yq/jq path as the seed of our query
		vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
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

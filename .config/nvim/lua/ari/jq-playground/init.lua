--- @class ari.jq-playground
--- Helpers and window management for jq-playground.nvim.
local M = {}

--- @class PlaygroundWins
--- @field query integer? Window ID of the query input
--- @field output integer? Window ID of the output display

--- Escape single quotes for embedding in a single-quoted shell string.
--- @param str string
--- @return string
function M.xq_escape(str)
	return str:gsub("'", "'\"'\"'")
end

--- Ensure a jq/yq path starts with "." for valid query syntax.
--- Returns "." for nil, empty, or "null" inputs.
--- @param s string?
--- @return string
function M.ensure_dot_prefix(s)
	if not s or s == "" or s == "null" then
		return "."
	end
	return s:match("^%.") and s or ("." .. s)
end

-- =============================================================================
-- Playground window management
-- =============================================================================

--- Close the jq/yq playground query and output windows in the current tab.
function M.close()
	local wins = vim.t.jqplayground_wins
	if not wins then
		vim.notify("No active playground in this tab", vim.log.levels.WARN)
		return
	end

	if wins.query and vim.api.nvim_win_is_valid(wins.query) then
		vim.api.nvim_win_close(wins.query, false)
	end
	if wins.output and vim.api.nvim_win_is_valid(wins.output) then
		vim.api.nvim_win_close(wins.output, false)
	end

	vim.t.jqplayground_wins = nil
end

--- Open a jq/yq playground seeded with a query string.
--- Reuses an existing playground window if one is open in the current tab.
--- @param xq_query string The query to seed the playground with
function M.open_seeded(xq_query)
	-- Reuse existing playground if open
	local wins = vim.t.jqplayground_wins
	if wins and wins.query and vim.api.nvim_win_is_valid(wins.query) then
		vim.api.nvim_set_current_win(wins.query)
		vim.schedule(function()
			vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
			vim.api.nvim_put({ xq_query }, "c", false, true)
		end)
		return
	end

	-- Track existing windows so we can identify the new ones
	local before = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		before[win] = true
	end

	vim.cmd.JqPlayground()

	vim.schedule(function()
		local query_win = vim.api.nvim_get_current_win()
		local output_win = nil
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if not before[win] and win ~= query_win then
				output_win = win
				break
			end
		end

		vim.t.jqplayground_wins = { query = query_win, output = output_win }
		vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
		vim.api.nvim_put({ xq_query }, "c", false, true)
	end)
end

--- Create a buffer-local keymap with a JqPlayground description prefix.
--- @param lhs string Key sequence
--- @param rhs string|function Action
--- @param desc string Description (prefixed with "JqPlayground: ")
--- @param opts? table Extra keymap options (mode, etc.)
function M.bufmap(lhs, rhs, desc, opts)
	opts = vim.tbl_extend("force", opts or {}, {
		buffer = true,
		desc = "JqPlayground: " .. desc,
	})
	local mode = opts.mode or "n"
	opts.mode = nil
	vim.keymap.set(mode, lhs, rhs, opts)
end

return M

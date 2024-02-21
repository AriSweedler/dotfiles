local M = {}

-- Function to determine if a line of text has an ANSI color code on it:
--
--     <ESC> [ <NUMBERS> m
--
-- Returns a bool
local function has_ansi_color_code(line)
	return line:match("\27%[[0-9;]*m") ~= nil
end

local function strip_ansi_color_code(line)
	return line:gsub("\27%[[0-9;]*m", "")
end

local function set_todocomments_jumping()
	local function jumper(key, keyword)
		vim.keymap.set("n", key, function()
			require("todo-comments").jump_next({ keywords = { keyword } })
		end, { desc = "Next " .. keyword .. " comment" })
	end
	local function loclister(key, keyword)
		vim.keymap.set("n", key, function()
			require("todo-comments").search({ keywords = { keyword } })
		end, { desc = "List " .. keyword .. " comments" })
	end

	jumper("W", "WARN")
	jumper("E", "ERROR")
	jumper("I", "INFO")
	loclister("<C-e>", "ERROR")
end

-- A lua function that takes no args. And it transforms the buffer according to
-- a regex. It looks at each line, if it has an ANSI color code and a timestamp
-- like so:
--
--     [33m2024-03-14T00:50:48.000Z [xxx] [yyy] LEVEL::[0m message
--
-- Then keep it, and strip the ANSI color codes.
-- Otherwise, discard it.
function M.filter_in_colorlogs()
	local buffer = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
	local new_lines = {}
	for _, line in ipairs(lines) do
		if has_ansi_color_code(line) then
			local new_line = strip_ansi_color_code(line)
			table.insert(new_lines, new_line)
		end
	end
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, new_lines)

	-- Set up todo-comments highlighting
	vim.bo.filetype = "log"
	set_todocomments_jumping()
end

return M

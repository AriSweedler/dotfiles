local log_levels = { "debug", "info", "warn", "error" }

local function get_current_log_level(line)
	for _, level in ipairs(log_levels) do
		if line:find("logger." .. level) then
			return level
		end
	end
end

local function get_next_log_level(current_level)
	for i, level in ipairs(log_levels) do
		if level == current_level then
			return log_levels[i % #log_levels + 1]
		end
	end
end

local function replace_log_level(line, current_level, next_level)
	return line:gsub("logger." .. current_level, "logger." .. next_level)
end

local M = {}

function M.cycle()
	local line = vim.api.nvim_get_current_line()
	local current_level = get_current_log_level(line)
	local next_level = get_next_log_level(current_level)
	local new_line = replace_log_level(line, current_level, next_level)
	vim.api.nvim_set_current_line(new_line)
end

return M

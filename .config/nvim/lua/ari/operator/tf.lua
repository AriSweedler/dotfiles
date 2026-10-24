---------------------------------------------------------------------------
-- Terraform box comment operator
---------------------------------------------------------------------------
-- Terraform box comment: always '#'
-- - Top/bottom bars are `vim.o.textwidth` wide (fallback 80, min 3)
-- - Content wraps to (textwidth - 2) and each wrapped line is prefixed with "# "
-- - Leading '#' + whitespace is removed before wrapping
local M = {}

local function normalize_whitespace(s)
	-- Trim and collapse internal whitespace to single spaces
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	s = s:gsub("%s+", " ")
	return s
end

local function wrap_paragraph(paragraph, width)
	-- Word-wrap a single paragraph to lines of at most `width` characters.
	-- Break at the last space <= width when possible; otherwise hard-wrap.
	local out = {}
	local s = paragraph
	while #s > 0 do
		if #s <= width then
			table.insert(out, s)
			break
		end
		local slice = s:sub(1, width)
		local break_at = slice:match(".*()%s") -- last whitespace position within slice
		if break_at then
			table.insert(out, slice:sub(1, break_at - 1))
			s = s:sub(break_at + 1):gsub("^%s+", "")
		else
			table.insert(out, slice)
			s = s:sub(width + 1)
		end
	end
	return out
end

--- Create a Terraform-style box comment from a buffer region.
--- Removes leading '#' and whitespace, then wraps text into a box comment:
--- - Top/bottom bars are textwidth wide (default 80, minimum 3)
--- - Content wraps to (textwidth - 2) with "# " prefix on each line
--- - Replaces the original buffer range with the boxed result
---@param bufnr number Buffer number (0 for current buffer)
---@param start0 number Start line (0-indexed, inclusive)
---@param end_excl number End line (0-indexed, exclusive)
function M.box(bufnr, start0, end_excl)
	---------------------------------------------------------------------------
	-- Collect & clean input
	---------------------------------------------------------------------------
	local lines = vim.api.nvim_buf_get_lines(bufnr, start0, end_excl, false)
	for i, line in ipairs(lines) do
		lines[i] = line:gsub("^%s*#+%s+", "")
	end

	-- Merge selected lines into a single normalized paragraph
	local paragraph = normalize_whitespace(table.concat(lines, " "))

	---------------------------------------------------------------------------
	-- Build the box
	---------------------------------------------------------------------------
	local textwidth = (vim.o.textwidth and vim.o.textwidth > 0) and vim.o.textwidth or 80
	if textwidth < 3 then textwidth = 3 end

	local bar = string.rep("#", textwidth)
	local boxed = { bar }

	if #paragraph > 0 then
		local wrap_width = math.max(1, textwidth - 2) -- space available after "# "
		for _, chunk in ipairs(wrap_paragraph(paragraph, wrap_width)) do
			table.insert(boxed, "# " .. chunk)
		end
	else
		-- If the selection is empty after stripping/normalizing, still include a blank content line
		table.insert(boxed, "# xxx")
	end

	table.insert(boxed, bar)

	---------------------------------------------------------------------------
	-- Replace buffer range
	---------------------------------------------------------------------------
	vim.api.nvim_buf_set_lines(bufnr, start0, end_excl, false, boxed)
end

return M

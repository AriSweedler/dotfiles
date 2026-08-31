-- Claude Code prompt buffers: highlight /skill invocations that name an installed
-- skill, and @path references that resolve to a real file. Both need
-- filesystem existence checks, so this uses extmarks instead of :syntax (which
-- treesitter disables anyway).

local ns = vim.api.nvim_create_namespace("claude_refs")
local skills_dir = vim.fs.normalize("~/.claude/skills")

-- Light blue to match Claude Code's own mention/command highlight, rather than
-- linking to colorscheme keyword groups.
local claude_blue = { default = true, fg = "#8ab4f8", ctermfg = 111 }
vim.api.nvim_set_hl(0, "ClaudeSkill", claude_blue)
vim.api.nvim_set_hl(0, "ClaudeFileRef", claude_blue)

local function installed_skills()
	local skills = {}
	local ok, iter = pcall(vim.fs.dir, skills_dir)
	if not ok then
		return skills
	end
	for name, kind in iter do
		if kind == "directory" then
			skills[name] = true
		end
	end
	return skills
end

-- Only regular files count; a directory reference isn't a useful @-mention.
local function is_file(path)
	local expanded = vim.fs.normalize(path)
	if not vim.startswith(expanded, "/") then
		expanded = vim.fs.joinpath(vim.fn.getcwd(), expanded)
	end
	local stat = vim.uv.fs_stat(expanded)
	return stat ~= nil and stat.type == "file"
end

-- A token only counts at a word boundary: start of line, or after whitespace/'('.
local function at_boundary(line, start)
	return start == 1 or line:sub(start - 1, start - 1):match("[%s(]") ~= nil
end

local function highlight_refs(buf)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local skills = installed_skills()
	for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local init = 1
		while true do
			local s, e, name = line:find("/([%w][%w:_-]*)", init)
			if not s then
				break
			end
			if at_boundary(line, s) and skills[name] then
				vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, s - 1, {
					end_col = e,
					hl_group = "ClaudeSkill",
					spell = false,
				})
			end
			init = e + 1
		end

		init = 1
		while true do
			local s, e, path = line:find("@([^%s@]+)", init)
			if not s then
				break
			end
			-- Trailing punctuation is prose, not path: "see @foo/bar.tsx, and ..."
			local trimmed = path:match("^(.-)[.,;:!?%)%]]*$")
			if at_boundary(line, s) and trimmed ~= "" and is_file(trimmed) then
				vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, s - 1, {
					end_col = s + #trimmed,
					hl_group = "ClaudeFileRef",
					spell = false,
				})
			end
			init = e + 1
		end
	end
end

local buf = vim.api.nvim_get_current_buf()
local group = vim.api.nvim_create_augroup("claude_refs_" .. buf, { clear = true })
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
	group = group,
	buffer = buf,
	callback = function()
		highlight_refs(buf)
	end,
})
highlight_refs(buf)

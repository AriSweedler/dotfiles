local M = {}

-- Each opener has:
--   name:  identifier
--   check: (pr_num, dir) → (true) | (false, err_msg)  - gates whether this opener applies
--   open:  (pr_num, dir) → ()                         - performs the open; only runs if check passed
-- M.open iterates in order; first opener whose check passes is used.
M.openers = {
	{
		name = "gh_pr_web",
		check = function(pr_num, dir)
			local r = vim.system({
				"gh", "pr", "view", pr_num, "--json", "number",
			}, { cwd = dir, text = true }):wait()
			if r.code ~= 0 then
				return false, "PR #" .. pr_num .. " not found via gh: " .. (r.stderr or "")
			end
			return true
		end,
		open = function(pr_num, dir)
			vim.system({ "gh", "pr", "view", pr_num, "--web" }, { cwd = dir }):wait()
		end,
	},
}

function M.open(pr_num, dir)
	local last_err
	for _, o in ipairs(M.openers) do
		local ok, err = o.check(pr_num, dir)
		if ok then
			o.open(pr_num, dir)
			return true, o.name
		end
		last_err = err
	end
	return false, last_err
end

return M

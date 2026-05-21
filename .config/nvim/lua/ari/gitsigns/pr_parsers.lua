local M = {}

-- Each pattern's first capture group must be the PR number.
-- Ordered most-specific to most-permissive.
M.patterns = {
	-- GitHub squash-merge: "Subject line (#12345)"
	{ name = "squash_merge", pattern = "%(#(%d+)%)%s*$" },
	-- GitHub merge commit: "Merge pull request #12345 from ..."
	{ name = "merge_commit", pattern = "^Merge pull request #(%d+) " },
}

function M.extract(subject)
	for _, p in ipairs(M.patterns) do
		local num = subject:match(p.pattern)
		if num then
			return num, p.name
		end
	end
	return nil
end

return M

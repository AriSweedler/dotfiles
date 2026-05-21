local pr_parsers = require("ari.gitsigns.pr_parsers")
local pr_openers = require("ari.gitsigns.pr_openers")

local function warn(msg) vim.notify(msg, vim.log.levels.WARN) end

local function blame_current_line()
	local file = vim.fn.expand("%:p")
	if file == "" then return nil, "No file in buffer" end
	local line = vim.fn.line(".")
	local dir = vim.fn.fnamemodify(file, ":h")

	local r = vim.system({
		"git", "blame", "-L", line .. "," .. line, "--porcelain", "--", file,
	}, { cwd = dir, text = true }):wait()
	if r.code ~= 0 then return nil, "git blame failed: " .. (r.stderr or "") end

	local sha = r.stdout:match("^(%S+)")
	if not sha then return nil, "Could not parse blame output" end
	if sha:match("^0+$") then return nil, "Line is uncommitted" end

	return { sha = sha, subject = r.stdout:match("\nsummary (.-)\n") or "", dir = dir }
end

local function confirm(prompt)
	vim.api.nvim_echo({ { prompt, "Question" } }, false, {})
	local ok, ch = pcall(vim.fn.getcharstr)
	vim.api.nvim_echo({ { "", "" } }, false, {})
	return ok and (ch == "y" or ch == "\r")
end

return function()
	local blame, err = blame_current_line()
	if not blame then return warn(err) end

	local pr_num = pr_parsers.extract(blame.subject)
	if not pr_num then return warn("No PR number in: " .. blame.subject) end

	local gs = package.loaded.gitsigns
	if not gs then return warn("gitsigns not loaded") end

	-- First call opens the blame popup; second call focuses into it.
	gs.blame_line({}, function()
		gs.blame_line({}, function()
			vim.schedule(function()
				if not confirm("Open PR #" .. pr_num .. "? [y/Enter] ") then return end
				local ok, open_err = pr_openers.open(pr_num, blame.dir)
				if not ok then return warn(open_err or ("Failed to open PR #" .. pr_num)) end
				vim.notify("Opened PR #" .. pr_num, vim.log.levels.INFO)
			end)
		end)
	end)
end

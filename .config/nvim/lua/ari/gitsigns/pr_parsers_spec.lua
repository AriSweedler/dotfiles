#!/usr/bin/env lua
-- Run with: lua ~/.config/nvim/lua/ari/gitsigns/pr_parsers_spec.lua

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
package.path = script_dir .. "../../?.lua;" .. package.path

local pr_parsers = require("ari.gitsigns.pr_parsers")

local pattern_by_name = {}
for _, p in ipairs(pr_parsers.patterns) do
	pattern_by_name[p.name] = p.pattern
end

-- cases: keyed by group name. Each group is a list of test records.
--
-- A group named after a parser ("squash_merge", "merge_commit") runs that
-- single parser's pattern against `input` and asserts the captured PR number
-- equals `expected` (string or nil).
--
-- The "extract" group runs pr_parsers.extract (iterates all parsers) and
-- asserts BOTH the captured number AND which parser matched. Records in this
-- group add a `parser` field naming the expected matcher (or nil for no match).
--
-- Record shape:
--   { input = <subject>, expected = <pr_num or nil>, parser = <name or nil> }
local cases = {
	-- matches "... (#N)" at end of subject
	squash_merge = {
		{ input = "Do the thing (#1001)", expected = "1001" },
		{ input = "Do the thing (#1002)  ", expected = "1002" },
		{ input = "feat(scope): do the thing (#1004)", expected = "1004" },
		{ input = "Merge pull request #1003 from owner/branch", expected = nil },
		{ input = "Reference #1 inline", expected = nil },
		{ input = "", expected = nil },
	},

	-- matches "Merge pull request #N ..." at start of subject
	merge_commit = {
		{ input = "Merge pull request #1003 from owner/branch", expected = "1003" },
		{ input = "Do the thing (#1001)", expected = nil },
		{ input = "Do the thing", expected = nil },
		{ input = "", expected = nil },
	},

	-- iterates all parsers, returns first match (and which parser matched)
	extract = {
		{ input = "Do the thing (#1001)", expected = "1001", parser = "squash_merge" },
		{ input = "Merge pull request #1003 from owner/branch", expected = "1003", parser = "merge_commit" },
		{ input = "Fix #1 regression (#1005)", expected = "1005", parser = "squash_merge" },
		{ input = "Reference #1 inline", expected = nil, parser = nil },
		{ input = "", expected = nil, parser = nil },
	},
}

local order = { "squash_merge", "merge_commit", "extract" }

local function run(group, input)
	if group == "extract" then
		return pr_parsers.extract(input)
	end
	return input:match(pattern_by_name[group]), nil
end

local function render(num, parser)
	if not num then return "no match" end
	if parser then return string.format("#%s (%s)", num, parser) end
	return "#" .. num
end

local total, failed = 0, 0
for _, group in ipairs(order) do
	for _, c in ipairs(cases[group]) do
		total = total + 1
		local got_num, got_parser = run(group, c.input)
		local ok = got_num == c.expected and (group ~= "extract" or got_parser == c.parser)
		if not ok then failed = failed + 1 end
		print(string.format(
			"%s  [%s]  %q\n      → %s%s",
			ok and "PASS" or "FAIL",
			group,
			c.input,
			render(got_num, got_parser),
			ok and "" or string.format("   (expected %s)", render(c.expected, c.parser))
		))
	end
end

print(string.format("\n%d/%d passed", total - failed, total))
os.exit(failed == 0 and 0 or 1)

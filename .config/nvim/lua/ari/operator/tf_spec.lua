#!/usr/bin/env lua
-- Run with: lua ~/.config/nvim/lua/ari/operator/tf_spec.lua
-- ari.operator.tf.box under plain Lua, with a stand-in buffer (vim.api get/set lines) and vim.o.textwidth.
-- Covers the bars at textwidth, wrapping at textwidth - 2 with "# ", stripping old '#' prefixes, collapsing
-- whitespace, a word longer than the line, an empty selection, the 80 fallback and the minimum of 3.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
package.path = script_dir .. "../../?.lua;" .. package.path
local buffer = {}
vim = {
	o = { textwidth = 0 },
	api = {
		nvim_buf_get_lines = function(_, s, e) local out = {} for i = s + 1, e do table.insert(out, buffer[i]) end return out end,
		nvim_buf_set_lines = function(_, s, e, _, repl)
			local out = {}
			for i = 1, s do table.insert(out, buffer[i]) end
			for _, l in ipairs(repl) do table.insert(out, l) end
			for i = e + 1, #buffer do table.insert(out, buffer[i]) end
			buffer = out
		end,
	},
}
local tf = require("ari.operator.tf")

local total, failed = 0, 0
local function check(name, expected, actual)
	total = total + 1
	local ok = expected == actual
	if not ok then failed = failed + 1 end
	print(string.format("%s  %s%s", ok and "PASS" or "FAIL", name,
		ok and "" or string.format("\n      expected %q\n      got      %q", tostring(expected), tostring(actual))))
end
local function box(lines, textwidth, first, last)
	buffer = lines
	vim.o.textwidth = textwidth
	tf.box(0, first or 0, last or #lines)
	return table.concat(buffer, "\n")
end

check("box: bars at textwidth, content after '# '", "##########\n# a b c\n##########", box({ "a b c" }, 10))
check("box: wraps at textwidth - 2 on a space", "##########\n# one two\n# three\n##########", box({ "one two three" }, 10))
check("box: old '#' prefixes and extra spaces go", "##########\n# a b\n##########", box({ "  ## a", "#   b   " }, 10))
check("box: a word longer than the line is cut", "#####\n# abc\n# def\n#####", box({ "abcdef" }, 5))
check("box: an empty selection gets a placeholder", "######\n# xxx\n######", box({ "#  ", "" }, 6))
check("box: textwidth 0 falls back to 80", string.rep("#", 80), box({ "x" }, 0):match("^[^\n]+"))
check("box: textwidth below 3 is 3", "###\n# x\n###", box({ "x" }, 2))
check("box: only the selected range is replaced", "keep\n######\n# mid\n######\nkeep", box({ "keep", "mid", "keep" }, 6, 1, 2))

print(string.format("\n%d/%d passed", total - failed, total))
os.exit(failed == 0 and 0 or 1)

#!/usr/bin/env lua
-- Run with: lua ~/.config/nvim/lua/ari/color/color_spec.lua
-- ari.color and ari.color.ize under plain Lua, with a stand-in for the one vim call they make on bad
-- input (nvim_err_writeln). Covers parsing and printing a hex color, the grey test, lightening towards
-- white, darkening that keeps the brightest channel visible, the grey ramp, and the gamut's 18 rows.

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
package.path = script_dir .. "../../?.lua;" .. script_dir .. "../../?/init.lua;" .. package.path
local errors = {}
vim = {
	api = { nvim_err_writeln = function(msg) table.insert(errors, msg) end },
	list_extend = function(dst, src) for _, v in ipairs(src) do table.insert(dst, v) end return dst end,
}
local Color = require("ari.color")
local Ize = require("ari.color.ize")

local total, failed = 0, 0
local function check(name, expected, actual)
	total = total + 1
	local ok = expected == actual
	if not ok then failed = failed + 1 end
	print(string.format("%s  %s%s", ok and "PASS" or "FAIL", name,
		ok and "" or string.format("\n      expected %s, got %s", tostring(expected), tostring(actual))))
end
local function hex(h, f) local c = Color:new(h); f(c); return c:to_hex() end

check("new/to_hex: round trip", "#1a2b3c", Color:new("#1A2B3C"):to_hex())
check("new: no '#' is nil", nil, Color:new("1a2b3c"))
check("new: and it says why", true, errors[#errors]:find("must start with '#'", 1, true) ~= nil)
check("new: non-hex digits are nil", nil, Color:new("#zzzzzz"))
check("is_grey: equal channels", true, Color:new("#777777"):is_grey())
check("is_grey: unequal channels", false, Color:new("#777778"):is_grey())

check("adjust_color 0: unchanged", "#336699", hex("#336699", function(c) c:adjust_color(0) end))
check("adjust_color 4: pure white", "#ffffff", hex("#336699", function(c) c:adjust_color(4) end))
check("adjust_color 2: halfway to white, rounded", "#ff8080", hex("#ff0000", function(c) c:adjust_color(2) end))
check("adjust_color 9: clamped to 4", "#ffffff", hex("#123456", function(c) c:adjust_color(9) end))
check("adjust_color -2: half as bright", "#1a334d", hex("#336699", function(c) c:adjust_color(-2) end))
check("adjust_color -4: the brightest channel stays at 50, not black", "#000032", hex("#0000ff", function(c) c:adjust_color(-4) end))
check("adjust_color -4 on red keeps red", "#320000", hex("#ff0000", function(c) c:adjust_color(-4) end))

check("adjust_grey +1: 20 points lighter", "#8b8b8b", hex("#777777", function(c) c:adjust_grey(1) end))
check("adjust_grey -9: clamped at black", "#000000", hex("#777777", function(c) c:adjust_grey(-9) end))
local before = #errors
hex("#ff0000", function(c) c:adjust_grey(1) end)
check("adjust_grey on a color warns", before + 1, #errors)

check("ize.colorize: a bad hex is nil", nil, Ize.colorize("nope", 1))
local rows = Ize.gamut(Color:new("#336699"))
check("gamut: nine greyscale rows and nine colorize rows", 18, #rows)
check("gamut: the first row", "Greyscale (-4): #000000", rows[1])
check("gamut: the colorize row at 0 is the seed", "Colorize  ( 0): #336699", rows[14])

print(string.format("\n%d/%d passed", total - failed, total))
os.exit(failed == 0 and 0 or 1)

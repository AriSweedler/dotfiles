-- If I'm holding shift, the action should linewise (Except for 'C', I'll allow
-- that one)
-- Linewise actions for shift key mappings
local shift_mappings = {
	D = "dd",
	Y = "yy",
	["<"] = "<<",
	[">"] = ">>",
}

-- Set up the mappings
for lhs, rhs in pairs(shift_mappings) do
	vim.keymap.set("n", lhs, rhs)
end

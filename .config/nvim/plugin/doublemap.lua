-- If I'm holding shift, the action should linewise (Except for 'C', I'll allow
-- that one)
local function shift_mappings()
	local map = {
		D = "dd",
		Y = "yy",
		["<"] = "<<",
		[">"] = ">>",
	}

	-- Set up the mappings
	for lhs, rhs in pairs(map) do
		vim.keymap.set("n", lhs, rhs)
	end
end

shift_mappings()

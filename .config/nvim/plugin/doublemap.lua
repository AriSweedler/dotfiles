local ari = require("ari")

-- Double stuff up:
-- Define double mappings
local double_mappings = {
	D = "dd",
	Y = "yy",
	["<"] = "<<",
	[">"] = ">>",
}

-- Set up the mappings
for lhs, rhs in pairs(double_mappings) do
	ari.map("n", lhs, rhs)
end

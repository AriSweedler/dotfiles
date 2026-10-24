local mr = require("mason-registry")

local M = {}

-- Use Mason to check if a package is installed. If it is not, install it.
M.ensure_installed = function(package_name)
	if mr.is_installed(package_name) then
		return
	end

	mr.get_package(package_name):install()
end

return M

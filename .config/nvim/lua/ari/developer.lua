local M = {}

local function exists(val, tab)
	for _, v in ipairs(tab) do
		if v == val then
			return true
		end
	end

	return false
end

local function find_scm_files(lang, query_type)
	local stub = string.format("queries/%s/%s.scm", lang, query_type)
	local files = vim.api.nvim_get_runtime_file(stub, true)

	-- Ensure there is a local file in this list. That means that we will give the
	-- user the option to create one, even if there's nothing there already and
	-- nothing installed
	local my_file = vim.fn.stdpath("config") .. string.format("/queries/%s/%s.scm", lang, query_type)
	if not exists(my_file, files) then
		table.insert(files, my_file)
	end
	return files
end

function M.edit_and_compare_ts_queries(query_type)
	local files = find_scm_files(vim.bo.filetype, query_type)
	vim.cmd.tabedit(files[1])
	for i = 2, #files do
		vim.cmd.vsplit(files[i])
	end
end

return M

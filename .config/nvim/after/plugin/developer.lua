-- Easy and consistent editing of all sorts of nvim files

-- | <Leader>ts | tabedit and vsp all the relevant treesitter query files
-- | f (fold),
--   h (highlight),
--   t (textobject)
--   ? (help)
local function ts_mappings()
	-- Define the grammar
	local treesitter_cmds = {
		{
			key = "f",
			scm = "folds",
		},
		{
			key = "h",
			scm = "highlights",
		},
		{
			key = "t",
			scm = "textobjects",
		},
	}

	-- Use the grammar to create all the mappings
	for _, target in pairs(treesitter_cmds) do
		local lhs = string.format("<Leader>ts%s", target.key)
		local desc = "[ari] [developer] [treesitter]: Compare and tabedit treesitter query files for " .. target.scm
		vim.keymap.set("n", lhs, function()
			-- Find all runtime files that match this stub
			local stub = string.format("after/queries/%s/%s.scm", vim.bo.filetype, target.scm)
			local files = vim.api.nvim_get_runtime_file(stub, true)

			-- Ensure there is a local file in this list.
			local my_file = vim.fn.stdpath("config") .. "/" .. stub
			if not vim.tbl_contains(files, my_file) then
				table.insert(files, my_file)
			end

			-- Open all files in a new tab:
			-- * tabedit the first file
			-- * vsplit all the other files.
			vim.cmd.tabedit(files[1])
			for i = 2, #files do
				vim.cmd.vsplit(files[i])
			end
		end, { desc = desc })
	end

	-- help
	vim.keymap.set("n", "<Leader>ts?", ":map <Leader>ts<Enter>", { desc = "[ari] [developer] [treesitter]: Help" })
end

-- Use the ':help %:h' patterns to place filename on clipboard
--
-- | <Leader>% | copies file path to clipboard
-- | h (head)
--   p (path)
--   t (tail)
--   r (root)
--   . (relative)
--   ? (help)
local function cb_mappings()
	-- Define the grammar
	local fname_modifiers = { "h", "p", "t", "r", "." }

	-- Use the grammar to create all the mappings
	for _, fname_modifier in ipairs(fname_modifiers) do
		local lhs = "<Leader>%" .. fname_modifier
		local d = "[ari] [developer]: Copy file path to clipboard"
		vim.keymap.set("n", lhs, function()
			vim.fn.setreg("+", vim.fn.expand("%:" .. fname_modifier))
		end, { desc = d })
	end

	-- help
	vim.keymap.set("n", "<Leader>%?", ":map <Leader>%<Enter>", { desc = "[ari] [developer]: Help" })
end

-- Invoke the mapping-creating functions
ts_mappings()
cb_mappings()

-- Easy and consistent editing of all sorts of nvim files

-- The grammar is:
--
-- | <Leader>{e,v,t,s} | {edit,split,vsplit,tabedit,source (lowercase only)}
-- | f (filetype),
--   v (vimrc init.lua),
--   o (current file)
--   L (nvim-lspconfig)
--   T (terminal)
--   ? (help)
local function tes_mappings()
	-- Define the grammar
	local mappings_hook = {
		e = "edit",
		S = "split",
		v = "vsplit",
		t = "tabedit",
		s = "source",
	}

	local ft = "<C-r>=&filetype<Enter>"
	local mappings_cmd = {
		{
			key = "f",
			desc = "filetype plugin",
			path = vim.fn.stdpath("config") .. "/after/ftplugin/" .. ft .. ".lua",
		},
		{
			key = "v",
			desc = "my init.vim file",
			path = "$MYVIMRC",
		},
		{
			key = "o",
			desc = "the current file",
			path = "%",
		},
		{
			key = "L",
			desc = "installed LSP configurations",
			path = vim.fn.stdpath("data") .. "/lazy/nvim-lspconfig/lua/lspconfig/server_configurations",
		},
		{
			key = "T",
			desc = "New terminal buffer",
			path = "term://zsh",
		},
	}

	-- Use the grammar to create all the mappings
	for key1, action in pairs(mappings_hook) do
		for _, target in pairs(mappings_cmd) do
			local lhs = string.format("<Leader>%s%s", key1, target.key)
			local rhs = string.format(":%s %s<Enter>", action, target.path)
			local d = "[ari] [developer]: " .. action .. " " .. target.desc
			vim.keymap.set("n", lhs, rhs, { desc = d })
		end

		-- help
		do
			local lhs = string.format("<Leader>%s?", key1)
			local rhs = string.format(":map <Leader>%s<Enter>", key1)
			vim.keymap.set("n", lhs, rhs, { desc = "[ari] [developer]: Help" })
		end
	end
end

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
		local desc = "[ari] [developer] [treesitter]: tabedit query files for " .. target.scm
		vim.keymap.set("n", lhs, function()
			-- Find all runtime files that match this stub
			local stub = string.format("queries/%s/%s.scm", vim.bo.filetype, target.scm)
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
tes_mappings()
ts_mappings()
cb_mappings()

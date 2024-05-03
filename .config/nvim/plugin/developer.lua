-- Easy editing of personal filetype plugins
-- The grammar is:
-- | <Leader>{e,t,s} | {edit,open in a new tab,source}
-- | f (filetype),
--   v (vimrc init.lua),
--   o (current file)
--   P (plugins),
--   S (snippets),
--   F (folds)

-- Helper functions
local ft = "<C-r>=&filetype<Enter>"
local ari = require("ari")

local function my_plugins_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*/)")
end

-- Grammar
local mappings_hook = {
	e = "edit",
	v = "vsplit",
	t = "tabedit",
	s = "source",
}

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
		key = "P",
		desc = "my personal plugins folder",
		path = my_plugins_path(),
	},
	{
		key = "D",
		desc = "my personal plugins folder (alias - developer)",
		path = my_plugins_path(),
	},
	{
		key = "Q",
		desc = "my treesitter queries",
		path = vim.fn.stdpath("config") .. "/queries",
	},
	{
		key = "S",
		desc = "my personal snippets",
		path = vim.fn.stdpath("config") .. "/snippets/package.json",
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

-- Set up the mappings using a loop
for key1, action in pairs(mappings_hook) do
	-- .lua files
	for _, target in pairs(mappings_cmd) do
		local lhs = string.format("<Leader>%s%s", key1, target.key)
		local rhs = string.format(":%s %s<Enter>", action, target.path)
		local d = "[ari] [developer]: " .. action .. " " .. target.desc
		ari.map("n", lhs, rhs, { desc = d })
	end

	-- help
	do
		local lhs = string.format("<Leader>%s?", key1)
		local rhs = string.format(":map <Leader>%s<Enter>", key1)
		ari.map("n", lhs, rhs, { desc = "[ari] [developer]: Help" })
	end
end

-- Edit and compare Treesitter files
vim.defer_fn(function()
	-- Grammar
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

	for _, target in pairs(treesitter_cmds) do
		local lhs = string.format("<Leader>ts%s", target.key)
		local d = "[ari] [developer] [treesitter]: Compare and tabedit treesitter query files: " .. target.scm
		ari.lua_map(
			"n",
			lhs,
			{ "ari.developer", "edit_and_compare_ts_queries", { '"' .. target.scm .. '"' } },
			{ desc = d }
		)
	end

	-- help
	ari.map("n", "<Leader>ts?", ":map <Leader>ts<Enter>", { desc = "[ari] [developer] [treesitter]: Help" })
end, 0)

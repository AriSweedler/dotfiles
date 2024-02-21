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
local function fold_file_from_pack(pack)
  return pack .. "/queries/" .. ft .. "/folds.scm"
end
local ari = require('ari')

local function my_plugins_path()
   local str = debug.getinfo(2, "S").source:sub(2)
   return str:match("(.*/)")
end

local function is_editing(action)
  return action == "edit" or action == "tabedit" or action == "vsplit"
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
    descr = "filetype plugin",
    path =  vim.fn.stdpath("config") .. "/after/ftplugin/" .. ft .. ".lua"
  },
  v = "$MYVIMRC", -- My init.vim file
  o = '%', -- current file
  P = my_plugins_path(), -- My personal plugins folder
  D = my_plugins_path(), -- My personal plugins folder (alias - developer)
  S = vim.fn.stdpath("config") .. "/snippets/package.json", -- My personal snippets
  L = vim.fn.stdpath("data") .. "/lazy/nvim-lspconfig/lua/lspconfig/server_configurations" -- Installed LSP configurations
}

-- Set up the mappings using a loop
for key1, action in pairs(mappings_hook) do

  -- .lua files
  for key2, file in pairs (mappings_cmd) do
    local lhs = string.format("<Leader>%s%s", key1, key2)
    local rhs = string.format(":%s %s<Enter>", action, file)
    ari.map('n', lhs, rhs)
  end

  if is_editing(action) then
    -- treesitter "fold" files
    local lhs = string.format("<Leader>%s%s", key1, 'zf')
    local file1 = fold_file_from_pack(vim.fn.stdpath("config") .. "/nvim-treesitter")
    local file2 = fold_file_from_pack(vim.fn.stdpath("data") .. "/lazy/nvim-treesitter")
    local rhs = string.format(":%s %s<Bar>vsp %s<Enter>", action, file1, file2)
    ari.map('n', lhs, rhs)
  end

  -- help
  do
    local lhs = string.format("<Leader>%s?", key1)
    local rhs = string.format(":map <Leader>%s<Enter>", key1)
    ari.map('n', lhs, rhs)
  end
end

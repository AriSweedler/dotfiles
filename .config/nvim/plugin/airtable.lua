-- Local plugin: symlinked from ~/h/source/airtable.nvim
if pcall(vim.cmd.packadd, "airtable.nvim") then
	require("airtable").setup()
end

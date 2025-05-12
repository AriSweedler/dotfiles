local function format_javalog()
	vim.cmd([[%!jq]])
	vim.cmd([[%substitute/\\n/\r/eg]])
	vim.cmd([[%substitute/\\t/\t/eg]])
end

vim.keymap.set("n", "<Leader><Leader>F", format_javalog, {
	desc = "Format a string pipeline. First through jq, and then expand '\\n\\t'",
})

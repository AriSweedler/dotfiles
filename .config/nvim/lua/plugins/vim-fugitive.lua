-- Return true if the path is a FILE and inside the 'dotfiles' repo
local function is_dotfile(path)
	-- Read the files that exist in the bare repo stored in ~/dotfiles
	local git_dir = vim.fn.expand("$HOME") .. "/dotfiles"
	local git = "git --git-dir='" .. git_dir .. "' "
	local dotfiles = vim.fn.systemlist(git .. "ls-tree --full-tree -r --name-only HEAD")
	-- Make the paths absolute by prepending '$HOME' to each entry
	for i, v in ipairs(dotfiles) do
		dotfiles[i] = vim.fn.expand("$HOME") .. "/" .. v
	end

	if vim.tbl_contains(dotfiles, path) then
		return true
	end
	return false
end

local M = {
	"tpope/vim-fugitive",
	event = "BufReadPre",
	config = function()
		vim.keymap.set("n", "gb", function()
			local flags = ""
			if is_dotfile(vim.fn.expand("%:p")) then
				-- TODO make this work
				print("THIS IS A DOTFILE - ADDING FLAGS TO GB")
				flags = " --git-dir='" .. vim.fn.expand("$HOME") .. "/dotfiles'"
			end
			-- Check to see
			print("Git blame" .. flags)
			vim.cmd("Git blame" .. flags)
			vim.cmd("vertical resize 25")
		end, { desc = "Fugitive: Git blame" })
	end,
}

return M

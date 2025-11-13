-- Return true if the path is a FILE and inside the 'dotfiles' repo
function is_dotfile(path)
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
			local restoreme = {
				fugitive_git_executable = vim.g.fugitive_git_executable,
				git_dir = vim.b.git_dir,
			}

			if is_dotfile(vim.fn.expand("%:p")) then
				vim.notify("Running 'Git blame' on a dotfile")
				local home = vim.fn.expand("$HOME")
				local git_dir = home .. "/dotfiles"
				vim.g.fugitive_git_executable = {
					"git",
					"--git-dir=" .. git_dir,
					"--work-tree=" .. home,
				}
				vim.b.git_dir = git_dir
			end

			-- Run the actual command
			vim.cmd("Git blame")
			vim.cmd("vertical resize 25")

			-- Restore
			vim.g.fugitive_git_executable = restoreme.fugitive_git_executable
			vim.b.git_dir = restoreme.git_dir
		end, { desc = "Fugitive: Git blame" })
	end,
}

return M

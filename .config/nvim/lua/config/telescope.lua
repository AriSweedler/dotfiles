require("telescope").setup({
	opts = {
		defaults = {
			mappings = {
				i = {
					["<C-;>"] = require("telescope.actions").send_to_loclist
						+ require("telescope.actions").open_loclist,
				},
			},
		},
	},
})

-- [[ Configure Telescope ]]
-- See `:help telescope` and `:help telescope.setup()`

-- Enable telescope fzf native, if installed
pcall(require("telescope").load_extension, "fzf")
pcall(require("telescope").load_extension, "ui-select")

-- Telescope live_grep in git root
-- Function to find the git root directory based on the current buffer's path
local function find_git_root()
	-- Use the current buffer's path as the starting point for the git search
	local current_file = vim.api.nvim_buf_get_name(0)
	local current_dir
	local cwd = vim.fn.getcwd()
	-- If the buffer is not associated with a file, return nil
	if current_file == "" then
		current_dir = cwd
	else
		-- Extract the directory from the current file's path
		current_dir = vim.fn.fnamemodify(current_file, ":h")
	end

	-- Find the Git root directory from the current file's path
	local git_root = vim.fn.systemlist("git -C " .. vim.fn.escape(current_dir, " ") .. " rev-parse --show-toplevel")[1]
	if vim.v.shell_error ~= 0 then
		print("Not a git repository. Searching on current working directory")
		return cwd
	end
	return git_root
end

-- Custom live_grep function to search in git root
local function live_grep_git_root()
	local git_root = find_git_root()
	if git_root then
		require("telescope.builtin").live_grep({
			search_dirs = { git_root },
		})
	end
end

-- Find files
vim.keymap.set("n", "<Leader>?", require("telescope.builtin").oldfiles, { desc = "[?] Find recently opened files" })
vim.keymap.set("n", "<C-b>", require("telescope.builtin").buffers, { desc = "[ ] Find existing buffers" })
vim.keymap.set("n", "<C-t>", require("telescope.builtin").git_files, { desc = "Search git files" })
vim.keymap.set("n", "<Leader><C-t>", require("telescope.builtin").find_files, { desc = "Search pwd files" })

-- Find open file
vim.keymap.set("n", "<Leader>S/", function()
	require("telescope.builtin").live_grep({
		grep_open_files = true,
		prompt_title = "Live Grep in Open Files",
	})
end, { desc = "[S]earch [/] in Open Files" })

-- Search through this file
vim.keymap.set("n", "<Leader>/", function()
	-- You can pass additional configuration to telescope to change theme, layout, etc.
	require("telescope.builtin").current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
		winblend = 10,
		previewer = false,
	}))
end, { desc = "[/] Fuzzily search in current buffer" })

-- Search through project
vim.api.nvim_create_user_command("LiveGrepGitRoot", live_grep_git_root, {})
vim.keymap.set("n", "<Leader>SG", ":LiveGrepGitRoot<cr>", { desc = "[S]earch by [G]rep on Git Root" })
vim.keymap.set("n", "<Leader>Sg", require("telescope.builtin").live_grep, { desc = "[S]earch by [G]rep" })
vim.keymap.set("n", "<Leader>Sw", require("telescope.builtin").grep_string, { desc = "[S]earch current [W]ord" })

-- Search through misc
vim.keymap.set("n", "<Leader>St", require("telescope.builtin").builtin, { desc = "[S]earch [T]elescope" })
vim.keymap.set("n", "<Leader>Sh", require("telescope.builtin").help_tags, { desc = "[S]earch [H]elp" })
vim.keymap.set("n", "<Leader>Sd", require("telescope.builtin").diagnostics, { desc = "[S]earch [D]iagnostics" })
vim.keymap.set("n", "<Leader>Sk", require("telescope.builtin").keymaps, { desc = "[S]earch [K]eymaps" })

vim.keymap.set("n", "<Leader>Sr", require("telescope.builtin").resume, { desc = "[S]earch [R]esume" })

local SNACK_DESC_PREFIX = "Snacks Picker"
local SNACK_LEADER = "<Leader>p"

local bufmap = function(lhs, rhs, desc, opts)
	opts = opts or {}
	local keymapOpts = opts.keymapOpts or {}

	if opts.no_leader == nil then
		lhs = SNACK_LEADER .. lhs
	end

	-- Expand `wik_min` into nested args.win.input.keys with { "i", "n" } mode
	if opts.wik_min then
		opts.args = opts.args or {}
		local args = opts.args
		args.win = args.win or {}
		args.win.input = args.win.input or {}
		args.win.input.keys = args.win.input.keys or {}
		args.actions = args.actions or {}

		for key, action in pairs(opts.wik_min) do
			local action_name = desc:lower():gsub("[^a-z]", "_")

			-- Use a built-in action or a user-supplied function
			if type(action) == "string" then
				action_name = action
			elseif type(action) == "function" then
				args.actions[action_name] = action
			end

			if action_name then
				args.win.input.keys[key] = {
					action_name,
					mode = { "i", "n" },
				}
			end
		end
	end

	-- Generate and extend opts with "desc"
	keymapOpts = vim.tbl_extend("force", keymapOpts, {
		desc = SNACK_DESC_PREFIX .. ": " .. desc,
	})

	-- if 'rhs' is a function, then create a closure to set the args
	if type(rhs) == "function" then
		local fn = rhs
		if opts.args then
			rhs = function()
				fn(opts.args)
			end
		else
			rhs = function()
				fn()
			end
		end
	end

	vim.keymap.set("n", lhs, rhs, keymapOpts)
end

local action_tabedit = function(picker)
	local selections = picker:selected({ fallback = true })
	for _, item in ipairs(selections) do
		if not item.file then
			vim.notify("No file found for keymap: " .. item.text, vim.log.levels.ERROR)
			return
		end
		vim.cmd("tabedit " .. vim.fn.fnameescape(item.file))
		vim.api.nvim_win_set_cursor(0, item.pos)
	end
	picker:close()
end

-- In the picker UI, you can hit `<ESC>` to enter normal mode.
-- <Alt-w> to cycle windows
-- <C-b>/<C-f> to scroll in preview
-- <C-w>K to move the picker UP (removes preview?)

return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	---@type snacks.Config
	opts = {
		picker = {
			win = {
				input = {
					keys = {
						["<C-l>"] = { "loclist", mode = { "i", "n" } },
						["<C-g>"] = { "close", mode = { "i", "n" } },
					},
				},
			},
		},
	},
	config = function(_, opts)
		local Snacks = require("snacks")
		local SnacksActions = require("snacks.picker.actions")
		Snacks.setup(opts)

		vim.keymap.set("n", "<Leader>bd", function()
			Snacks.bufdelete()
		end, { desc = "Snacks: Close Buffer" })

		SNACK_DESC_PREFIX = "Snacks Picker"
		SNACK_LEADER = "<Leader>p"
		bufmap("<C-b>", Snacks.picker.buffers, "Buffers", {
			no_leader = true,
			wik_min = { ["<C-d>"] = "bufdelete" },
		})
		bufmap('"', Snacks.picker.registers, "Registers")
		bufmap("/", Snacks.picker.search_history, "Search History")
		bufmap("a", Snacks.picker.autocmds, "Autocmds")
		bufmap("b", Snacks.picker.buffers, "Buffers", { wik_min = { ["<C-d>"] = "bufdelete" } })
		bufmap("c", Snacks.picker.command_history, "Command History")
		bufmap("C", Snacks.picker.commands, "All possible commands")
		bufmap("<Leader>c", Snacks.picker.colorschemes, "Colorschemes")
		bufmap("d", Snacks.picker.diagnostics_buffer, "Buffer diagnostics")
		bufmap("D", Snacks.picker.diagnostics, "All diagnostics")
		bufmap("e", Snacks.picker.explorer, "File Explorer")
		bufmap("g", Snacks.picker.grep, "Grep")
		bufmap("h", Snacks.picker.help, "Help pages")
		bufmap("H", Snacks.picker.highlights, "Highlights")
		bufmap("i", Snacks.picker.icons, "Icons")
		bufmap("j", Snacks.picker.jumps, "Jump List")
		bufmap("k", Snacks.picker.keymaps, "Keymaps", { wik_min = { ["<C-t>"] = action_tabedit, } })
		bufmap("l", Snacks.picker.loclist, "Location List")
		bufmap("m", Snacks.picker.marks, "Marks")
		bufmap("M", Snacks.picker.man, "Man Pages")
		bufmap("n", Snacks.picker.notifications, "Notification History")
		bufmap("u", Snacks.picker.undo, "Undo History")

		SNACK_DESC_PREFIX = "Snacks Search Pickers"
		SNACK_LEADER = "<Leader>ps"
		bufmap("b", Snacks.picker.lines, "current buffer")
		bufmap("B", Snacks.picker.grep_buffers, "All open buffers")
		bufmap("p", Snacks.picker.lazy, "Plugins from Lazy package manager")

		-- LSP
		SNACK_DESC_PREFIX = "Snacks LSP Pickers"
		SNACK_LEADER = "gr"
		bufmap("d", Snacks.picker.lsp_definitions, "Goto Definition")
		bufmap("D", Snacks.picker.lsp_declarations, "Goto Declaration")
		bufmap("r", Snacks.picker.lsp_references, "Goto References")
		bufmap("i", Snacks.picker.lsp_implementations, "Goto Implementation")
		bufmap("y", Snacks.picker.lsp_type_definitions, "Goto Type Definition")
		bufmap("s", Snacks.picker.lsp_symbols, "Symbols")
		bufmap("S", Snacks.picker.lsp_workspace_symbols, "Workspace Symbols")

		-- Files
		SNACK_DESC_PREFIX = "Snacks File Picker"
		SNACK_LEADER = "<C-t>"
		bufmap("<C-t>", Snacks.picker.smart, "Smart Find Files")
		bufmap("r", Snacks.picker.recent, "Recent files")
		bufmap("f", Snacks.picker.files, "Files")
		bufmap("v", Snacks.picker.files, "Vim config files", {
			args = { cwd = vim.fn.stdpath("config") },
		})
		bufmap("d", function()
			require("plugins.snacks.picker").git_files({
				title = "Dotfiles",
				git_dir = vim.fn.expand("$HOME/dotfiles"),
				work_tree = vim.fn.expand("$HOME"),
			})
		end, "Dotfiles")
		bufmap("g", Snacks.picker.git_files, "Find git files")
		bufmap("p", Snacks.picker.projects, "Projects")

		-- Git
		SNACK_DESC_PREFIX = "Snacks Git Picker"
		SNACK_LEADER = "<Leader>pg"
		bufmap("b", Snacks.picker.git_branches, "Branches")
		bufmap("l", Snacks.picker.git_log, "Log")
		bufmap("L", Snacks.picker.git_log_line, "Log Line")
		bufmap("s", Snacks.picker.git_status, "Status")
		bufmap("S", Snacks.picker.git_stash, "Stash")
		bufmap("d", Snacks.picker.git_diff, "Diff (Hunks)")
		bufmap("f", Snacks.picker.git_log_file, "Log File")
	end,
	init = function()
		vim.api.nvim_create_autocmd("User", {
			pattern = "VeryLazy",
			callback = function()
				local Snacks = require("snacks")

				-- Setup some globals for debugging (lazy-loaded)
				_G.dd = function(...)
					Snacks.debug.inspect(...)
				end
				_G.bt = function()
					Snacks.debug.backtrace()
				end
				vim.print = _G.dd -- Override print to use snacks for `:=` command
			end,
		})
	end,
}

local bm = require("plugins.snacks.bufmap")
local actions = require("plugins.snacks.actions")

-- In the picker UI, you can hit `<ESC>` to enter normal mode.
-- <Alt-w> to cycle windows
-- <C-B>/<C-F> to scroll in preview
-- <C-W>K to move the picker UP (removes preview?)

return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	---@type snacks.Config
	opts = {
		gh = {},
		picker = {
			win = {
				input = {
					keys = {
						["<C-L>"] = { "loclist", mode = { "i", "n" } },
						["<C-G>"] = { "close", mode = { "i", "n" } },
					},
				},
			},
		},
	},

	config = function(_, opts)
		local Snacks = require("snacks")
		Snacks.setup(opts)

		vim.keymap.set("n", "<Leader>bd", function()
			Snacks.bufdelete()
		end, { desc = "Snacks: Close Buffer" })

		bm.block("Snacks Picker", "<Leader>p", function(bufmap)
			bufmap("<C-B>", Snacks.picker.buffers, "Buffers", {
				no_leader = true,
				wik_min = { ["<C-D>"] = "bufdelete" },
			})
			bufmap('"', Snacks.picker.registers, "Registers", { wik_min = { ["<C-E>"] = actions.edit_register } })
			bufmap("/", Snacks.picker.search_history, "Search History")
			bufmap("a", Snacks.picker.autocmds, "Autocmds")
			bufmap("b", Snacks.picker.buffers, "Buffers", { wik_min = { ["<C-D>"] = "bufdelete" } })
			bufmap("c", Snacks.picker.command_history, "Command History")
			bufmap("C", Snacks.picker.commands, "All possible commands")
			bufmap("<Leader>c", Snacks.picker.colorschemes, "Colorschemes")
			bufmap("d", Snacks.picker.diagnostics_buffer, "Buffer diagnostics")
			bufmap("D", Snacks.picker.diagnostics, "All diagnostics")
			bufmap("e", Snacks.picker.explorer, "File Explorer")
			bufmap("G", Snacks.picker.grep_buffers, "Grep open buffers")
			bufmap("<Leader>g", Snacks.picker.lines, "current buffer")
			bufmap("<Leader>G", Snacks.picker.grep, "Grep globally")
			bufmap("h", Snacks.picker.help, "Help pages")
			bufmap("H", Snacks.picker.highlights, "Highlights")
			bufmap("i", Snacks.picker.icons, "Icons")
			bufmap("j", Snacks.picker.jumps, "Jump List")
			bufmap("k", Snacks.picker.keymaps, "Keymaps", { wik_min = { ["<C-T>"] = actions.tabedit } })
			bufmap("l", Snacks.picker.loclist, "Location List")
			bufmap("m", Snacks.picker.marks, "Marks")
			bufmap("M", Snacks.picker.man, "Man Pages")
			bufmap("p", function() Snacks.picker.gh_pr({ author = "@me" }) end, "My Pull Requests")
			bufmap("P", Snacks.picker.lazy, "Plugins from Lazy package manager")
			bufmap("n", Snacks.picker.notifications, "Notification History")
			bufmap("u", Snacks.picker.undo, "Undo History")
			bufmap("y", require("yaml_nvim").snacks, "Yaml keys", { enabled_fxn = bm.can_require("yaml_nvim") })
		end)

		bm.block("Snacks LSP Pickers", "gr", function(bufmap)
			bufmap("d", Snacks.picker.lsp_definitions, "Goto Definition")
			bufmap("D", Snacks.picker.lsp_declarations, "Goto Declaration")
			bufmap("r", Snacks.picker.lsp_references, "Goto References")
			bufmap("i", Snacks.picker.lsp_implementations, "Goto Implementation")
			bufmap("y", Snacks.picker.lsp_type_definitions, "Goto Type Definition")
			bufmap("s", Snacks.picker.lsp_symbols, "Symbols")
			bufmap("S", Snacks.picker.lsp_workspace_symbols, "Workspace Symbols")
		end)

		bm.block("Snacks File Picker", "<C-T>", function(bufmap)
			bufmap("<C-T>", Snacks.picker.smart, "Smart Find Files")
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
			bufmap("l", Snacks.picker.files, nil, {
				args = {
					cwd = vim.fn.expand("$XDG_DATA_HOME"),
					title = "Local config files (XDG_DATA_HOME)"
				}
			})
			bufmap("g", Snacks.picker.git_files, "Find git files")
			bufmap("p", Snacks.picker.projects, "Projects")
		end)

		bm.block("Snacks Git Picker", "<Leader>pg", function(bufmap)
			bufmap("b", Snacks.picker.git_branches, "Branches")
			bufmap("l", Snacks.picker.git_log, "Log")
			bufmap("L", Snacks.picker.git_log_line, "Log Line")
			bufmap("s", Snacks.picker.git_status, "Status")
			bufmap("S", Snacks.picker.git_stash, "Stash")
			bufmap("d", Snacks.picker.git_diff, "Diff (Hunks)")
			bufmap("f", Snacks.picker.git_log_file, "Log File")
			bufmap("i", Snacks.picker.gh_issue, "GitHub Issues (open)")
			bufmap("I", function() Snacks.picker.gh_issue({ state = "all" }) end, "GitHub Issues (all)")
			bufmap("p", Snacks.picker.gh_pr, "GitHub Pull Requests (open)")
			bufmap("P", function() Snacks.picker.gh_pr({ state = "all" }) end, "GitHub Pull Requests (all)")
		end)
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

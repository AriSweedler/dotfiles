vim.g.mapLeader = "\\"
vim.g.maplocalLeader = "\\"

-- Just for me
vim.keymap.set("n", "*", "*N")
vim.keymap.set("n", "g*", "<Leader>Sw")

-- Basic config
vim.cmd("colorscheme evening")
vim.o.number = true
vim.o.relativenumber = true

-- Save undo history
vim.o.undofile = true

-- Set clipboard to use the system clipboard
vim.o.clipboard = "unnamedplus"

-- Keep signcolumn on by default
vim.wo.signcolumn = "yes"

vim.o.termguicolors = true

-- Lol no
vim.o.mouse = ""

-- Open new splits to the right
vim.o.splitright = true
vim.o.splitbelow = true

-- Let the terminal set the background color
vim.api.nvim_set_hl(0, "Normal", { bg = "None" })

-- Set listchars for spaces and tabs
vim.opt.listchars = { space = ".", tab = "|>" }

-- Install the setup manager 'Lazy' if needed.
-- Add it to runtime path
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	"tpope/vim-fugitive",
	"tpope/vim-sleuth",
	"tpope/vim-scriptease",
	"samoshkin/vim-mergetool",
	"vim-scripts/xterm-color-table.vim",
	"HiPhish/jinja.vim",

	{ -- Copilot
		"zbirenbaum/copilot.lua",
		cmd = "Copilot",
		event = "InsertEnter",
		config = function()
			require("copilot").setup({
				suggestion = {
					keymap = {
						accept = "<M-l>",
						accept_word = false,
						accept_line = false,
						next = "<M-]>",
						prev = "<M-[>",
					},
				},
				filetypes = {
					yaml = true,
				},
			})
		end,
	},

	{ -- statusline
		"nvim-lualine/lualine.nvim",
		opts = {
			options = {
				theme = "wombat",
				path = 1,
			},
			sections = {
				lualine_y = { "copilot", "progress" },
			},
		},
		dependencies = {
			"AndreM222/copilot-lualine",
		},
	},

	{ -- Autoformat
		"stevearc/conform.nvim",
		opts = {
			notify_on_error = false,
			format_on_save = {
				timeout_ms = 500,
				lsp_fallback = true,
			},
			formatters_by_ft = {
				lua = { "stylua" },
				-- python = { "black" },
			},
		},
	},

	{ -- LSP Configuration & Plugins
		"neovim/nvim-lspconfig",
		dependencies = {
			-- Install LSPs to stdpath for neovim
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			"WhoIsSethDaniel/mason-tool-installer.nvim",

			-- Useful status updates for LSP
			{ "j-hui/fidget.nvim", opts = {} },

			-- Additional lua configuration
			"folke/neodev.nvim",
		},
		config = function()
			require("config.nvim-lspconfig")
		end,
	},

	{ -- Autocompletion
		"hrsh7th/nvim-cmp",
		dependencies = {
			-- Snippet Engine & its associated nvim-cmp source
			"L3MON4D3/LuaSnip",
			"saadparwaiz1/cmp_luasnip",

			-- Adds LSP completion capabilities
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-path",
		},
	},

	{ -- Highlight, edit, and navigate code
		"nvim-treesitter/nvim-treesitter",
		dependencies = {
			"nvim-treesitter/nvim-treesitter-textobjects",
		},
		build = ":TSUpdate",
	},

	{ -- Git object actions + gutter signs
		"lewis6991/gitsigns.nvim",
		opts = {
			numhl = true,
			on_attach = require("config.gitsigns").on_attach_hook, -- set up keymaps
			worktrees = {
				{ -- My dotfiles
					toplevel = vim.env.HOME,
					gitdir = vim.env.HOME .. "/dotfiles",
				},
			},
		},
	},

	{
		"nvim-telescope/telescope.nvim",
		branch = "0.1.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "make",
				cond = function()
					return vim.fn.executable("make") == 1
				end,
			},
			{ "nvim-telescope/telescope-ui-select.nvim" },
			{ "nvim-tree/nvim-web-devicons" },
		},
		config = function()
			require("config.telescope")
		end,
	},

	{ -- Highlight todo, notes, etc in comments
		"folke/todo-comments.nvim",
		event = "VimEnter",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			keywords = {
				ERROR = { icon = " ", color = "error" },
				ARISWEEDLER_TODO = { icon = " ", color = "warning" },
			},
			signs = false,
		},
	},

	{
		"echasnovski/mini.nvim",
		config = function()
			require("config.mini")
		end,
	},
}, {})

-- Diagnostic keymaps
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous diagnostic message" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next diagnostic message" })
vim.keymap.set("n", "<Leader>e", vim.diagnostic.open_float, { desc = "Open floating diagnostic message" })
vim.keymap.set("n", "<Leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostics list" })

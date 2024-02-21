vim.g.mapLeader = '\\'
vim.g.maplocalLeader = '\\'

-- Just for me
vim.keymap.set('n', '*', '*N')
vim.keymap.set('n', 'g*', '<Leader>Sw')

-- Basic config
vim.cmd('colorscheme evening')
vim.o.number = true
vim.o.relativenumber = true

-- Save undo history
vim.o.undofile = true

-- Set clipboard to use the system clipboard
vim.o.clipboard = 'unnamedplus'

-- Keep signcolumn on by default
vim.wo.signcolumn = 'yes'

-- Set completeopt to have a better completion experience
-- vim.o.completeopt = 'menuone'

-- NOTE: You should make sure your terminal supports this
vim.o.termguicolors = true

-- Lol no
vim.o.mouse = ""

-- Open new splits to the right
vim.o.splitright = true

-- Let the terminal set the background color
vim.api.nvim_set_hl(0, 'Normal', { bg="None" })

-- Set listchars for spaces and tabs
vim.opt.listchars = { space = '.', tab = '|>' }

-- Install all plugins using 'lazy'
vim.opt.rtp:prepend(vim.fn.stdpath 'data' .. '/lazy/lazy.nvim')
require("lazy").setup({
  'tpope/vim-fugitive',
  'tpope/vim-sleuth',
  'tpope/vim-scriptease',
  'samoshkin/vim-mergetool',
  'vim-scripts/xterm-color-table.vim',
  -- 'github/copilot.vim',
  -- 'preservim/vim-markdown',

  {
    -- LSP Configuration & Plugins
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Install LSPs to stdpath for neovim
      { 'williamboman/mason.nvim', config = true },
      'williamboman/mason-lspconfig.nvim',

      -- Useful status updates for LSP
      { 'j-hui/fidget.nvim', opts = {} },

      -- Additional lua configuration
      'folke/neodev.nvim',
    },
  },
  {
    -- Autocompletion
    'hrsh7th/nvim-cmp', -- UNVETTED
    dependencies = {
      -- Snippet Engine & its associated nvim-cmp source
      'L3MON4D3/LuaSnip', -- UNVETTED
      'saadparwaiz1/cmp_luasnip', -- UNVETTED

      -- Adds LSP completion capabilities
      'hrsh7th/cmp-nvim-lsp', -- UNVETTED
      'hrsh7th/cmp-path', -- UNVETTED
    },
  },
  { -- statusline
    'nvim-lualine/lualine.nvim',
    opts = {
      options = {
        theme = 'wombat',
        path = 1,
      },
    },
  },

  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    dependencies = {
      'nvim-treesitter/nvim-treesitter-textobjects',
    },
    build = ':TSUpdate',
  },

  -- Use kickstart's simple autoformatting plugin
  -- /Users/ari.sweedler/.config/nvim/kickstart.lua/lua/kickstart/plugins/autoformat.lua
  -- require 'kickstart.plugins.autoformat',

  -- NOTE: The import below can automatically add your own plugins, configuration, etc from `lua/custom/plugins/*.lua`
  --    You can use this folder to prevent any conflicts with this init.lua if you're interested in keeping
  --    up-to-date with whatever is in the kickstart repo.
  --    Uncomment the following line and add your plugins to `lua/custom/plugins/*.lua` to get going.
  --
  --    For additional information see: https://github.com/folke/lazy.nvim#-structuring-your-plugins
  -- { import = 'custom.plugins' },

  { -- UNVETTED
    -- Adds git related signs to the gutter, as well as utilities for managing changes
    'lewis6991/gitsigns.nvim',
    opts = {
      -- See `:help gitsigns.txt`
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      on_attach = require('config.gitsigns').on_attach_hook,
    },
  },

  {
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
    },
    opts = {
      defaults = {
        mappings = {
          i = {
            ["<C-q>"] = "send_to_loclist + open_loclist",
          },
        },
      },
    },
  },
}, {})

-- Diagnostic keymaps
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous diagnostic message' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next diagnostic message' })
vim.keymap.set('n', '<Leader>e', vim.diagnostic.open_float, { desc = 'Open floating diagnostic message' })
vim.keymap.set('n', '<Leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })

---------- UNVETTED
-- [[ Configure nvim-cmp ]]
-- See `:help cmp`
local cmp = require 'cmp'
local luasnip = require 'luasnip'
require("luasnip.loaders.from_vscode").lazy_load({paths = "~/.config/nvim/snippets"})

luasnip.config.setup {}

cmp.setup {
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  completion = {
    completeopt = 'menu,menuone',
  },
  mapping = cmp.mapping.preset.insert {
    ['<C-n>'] = cmp.mapping.select_next_item(),
    ['<C-p>'] = cmp.mapping.select_prev_item(),
    ['<C-b>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete {},
    ['<CR>'] = cmp.mapping.confirm {
      behavior = cmp.ConfirmBehavior.Replace,
      select = true,
    },
    ['<Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif luasnip.expand_or_locally_jumpable() then
        luasnip.expand_or_jump()
      else
        fallback()
      end
    end, { 'i', 's' }),
    ['<S-Tab>'] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_prev_item()
      elseif luasnip.locally_jumpable(-1) then
        luasnip.jump(-1)
      else
        fallback()
      end
    end, { 'i', 's' }),
  },
  sources = {
    { name = 'luasnip' },
    { name = 'nvim_lsp' },
    { name = 'path' },
  },
}
---------- UNVETTED

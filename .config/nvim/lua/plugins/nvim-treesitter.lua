local function disable_ts_highlight_fxn(lang, buf)
	local max_filesize = 100 * 1024 -- 100 KB
	local filename = vim.api.nvim_buf_get_name(buf)
	local ok, stats = pcall(vim.loop.fs_stat, filename)
	if ok and stats and stats.size > max_filesize then
		vim.api.nvim_echo(
			{ { "We will not try to highlight " .. filename .. " because it is too big.", "Warning" } },
			true,
			{}
		)
		return true
	end
end

-- Generate the config for move from a grammar.
-- KEY_START := DIRECTION OBJ
-- KEY_END := DIRECTION TRANSFORM(OBJ)
--
-- For example, you can go to:
-- * PREV method START: [m
-- * PREV method END..: [M
-- * NEXT method START: ]m
-- * NEXT method END..: ]M
--
-- Here, 'm' means 'method' and the transform is capitalization
local function opts_textobjects_move()
	local objects = {
		m = "function",
		c = "class",
		a = "parameter",
	}
	local directions = {
		previous = "[",
		next = "]",
	}

	-- Iterate through the objects and directions to generate the keymaps
	local ans = {
		enable = true,
		set_jumps = true, -- whether to set jumps in the jumplist
	}
	for k, objn in pairs(objects) do
		for pn, blbr in pairs(directions) do
			for se, key in pairs({ start = k, ["end"] = string.upper(k) }) do
				local maneuver = "goto_" .. pn .. "_" .. se
				ans[maneuver] = ans[maneuver] or {}
				ans[maneuver][blbr .. key] = "@" .. objn .. ".outer"
			end
		end
	end

	return ans
end

local M = {
	"nvim-treesitter/nvim-treesitter",
	build = ":TSUpdate",
	event = "BufReadPost",
	dependencies = {
		"nvim-treesitter/nvim-treesitter-textobjects",
		"nvim-treesitter/nvim-treesitter-refactor",
	},
	opts = {
		auto_install = true,
		ensure_installed = "all",
		sync_install = true, -- Install parsers syncronously. Lol.
		ignore_install = {}, -- List of parsers to ignore installation
		highlight = {
			enable = true,
			disable = disable_ts_highlight_fxn,
		},
		indent = { enable = true },
		autopairs = { enable = true },
		autotag = { enable = true },
		refactor = {
			smart_rename = {
				enable = true,
				keymaps = {
					smart_rename = "grr",
				},
			},
			navigation = {
				enable = true,
				keymaps = {
					goto_next_usage = "]gd",
					goto_previous_usage = "[gd",
				},
			},
		},
		textobjects = {
			select = {
				enable = true,

				-- Automatically jump forward to textobjects, similar to targets.vim
				lookahead = true,

				keymaps = {
					-- You can use the capture groups defined in textobjects.scm
					["ia"] = { query = "@parameter.inner", desc = "Select inner part of a parameter" },
					["aa"] = { query = "@parameter.outer", desc = "Select outer part of a parameter" },
				},
				include_surrounding_whitespace = true,
			},
			swap = {
				enable = true,
				swap_next = { ["<Leader>]a"] = "@parameter.inner" },
				swap_previous = { ["<Leader>[a"] = "@parameter.inner" },
			},
			move = opts_textobjects_move(),
			lsp_interop = {
				enable = true,
				floating_preview_opts = { border = "rounded" },
				peek_definition_code = {
					["<leader>gd"] = "@function.outer",
					["<leader>gD"] = "@class.outer",
				},
			},
		},
	},
	config = function(_, opts)
		require("nvim-treesitter.configs").setup(opts)
	end,
}

return M

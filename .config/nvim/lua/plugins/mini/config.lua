-- Better Around/Inside textobjects
--
-- Examples:
--  - va)  - [V]isually select [A]round [)]paren
--  - yinq - [Y]ank [I]nside [N]ext [']quote
--  - ci'  - [C]hange [I]nside [']quote
--
--  ALSO:
--  - g[XXX - go to the start of the next text object
--  - g]XXX - go to the end of the next text object
require("mini.ai").setup({ n_lines = 500 })

-- Add/delete/replace/highlight surroundings (brackets, quotes, etc.)
--
-- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
-- - sd'   - [S]urround [D]elete [']quotes
-- - srp)'  - [S]urround [R]eplace [P]rev [)] [']
require("mini.surround").setup({
	highlight_duration = 1500,
	mappings = {
		suffix_last = "p", -- I say it is 'prev/next', NOT 'last/next'
	},
	respect_selection_type = true,
})

-- Extend f, F, t, T to work on multiple lines.
--
-- Repeat jump by pressing f, F, t, T again. It is reset when cursor moved as a
-- result of not jumping or timeout after idle time (duration customizable).
require("mini.jump").setup({
	delay = {
		-- Delay between jump and highlighting all possible jumps
		highlight = 250,

		-- Delay between jump and automatic stop if idle (no jump is done)
		idle_stop = 3000,
	},
})

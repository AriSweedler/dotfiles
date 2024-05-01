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

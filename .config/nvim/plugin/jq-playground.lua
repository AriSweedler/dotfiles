vim.pack.add({
	"https://github.com/yochem/jq-playground.nvim",
	"https://github.com/phelipetls/jsonpath.nvim",
})

require("jq-playground").setup({})
require("jsonpath").setup({ show_on_winbar = true })

local jq = require("ari.jq-playground")
local bufmap = jq.bufmap

-- =============================================================================
-- Path expressions: lua expressions that return the structured path at cursor.
-- Used both from vimscript (winbar) and lua (keymaps).
-- =============================================================================

local path_exprs = {
	json = "require'jsonpath'.get()",
	yaml = "require'ari.yaml_utils'.get_yaml_key_at_cursor()",
}
path_exprs.jsonl = path_exprs.json

-- =============================================================================
-- Filetype autocmds
-- =============================================================================

-- jq/yq query buffers
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "jq", "yq" },
	callback = function()
		bufmap("Y", function()
			local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			local escaped = jq.xq_escape(table.concat(lines, "\n"))
			local cmd = vim.o.filetype .. " '" .. escaped .. "' " .. vim.api.nvim_buf_get_name(vim.b.jqplayground_inputbuf)
			vim.fn.setreg("+", cmd)
			vim.notify("Copied " .. vim.o.filetype .. " command: " .. cmd, vim.log.levels.INFO)
		end, "Copy as shell command")

		bufmap("q", jq.close, "Close playground")
		bufmap("<C-f>", "<Plug>(JqPlaygroundRunQuery)", "Run query", { mode = { "i", "n" } })

		vim.bo.buftype = "nofile"
		vim.bo.swapfile = false
		vim.bo.bufhidden = "hide"
	end,
})

-- Data files (json, yaml)
vim.api.nvim_create_autocmd("FileType", {
	pattern = vim.tbl_keys(path_exprs),
	callback = function()
		local expr = path_exprs[vim.bo.filetype]
		local get_path = assert(load("return " .. expr))

		bufmap("Q", function()
			jq.open_seeded(jq.ensure_dot_prefix(get_path()))
		end, "Open with jq query to path pre-seeded")
		bufmap("<Leader>Q", vim.cmd.JqPlayground, "Open")

		vim.wo.winbar = "%{%v:lua." .. expr .. "%}"
		bufmap("I", function() vim.cmd("InspectTree") end, "Open InspectTree")
		bufmap("Y", function()
			local path = get_path()
			vim.fn.setreg("+", path)
			vim.notify("Copied " .. vim.bo.filetype .. " path: '" .. path .. "'", vim.log.levels.INFO)
		end, "Copy " .. vim.bo.filetype .. " path")
	end,
})

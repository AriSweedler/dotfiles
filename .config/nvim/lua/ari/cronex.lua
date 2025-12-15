local M = {}
local ns = vim.api.nvim_create_namespace("cronex-virtual-text")
local cache = {}

local set_virtual_text = function(bufnr, lnum, text)
	vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
		virt_text = { { "  " .. text, "LspInlayHint" } },
		virt_text_pos = "eol",
	})
end

local display_cron_explanation = function(bufnr, lnum, explanation)
	vim.diagnostic.reset(ns, bufnr)
	set_virtual_text(bufnr, lnum, explanation)
end

local handle_cron_expression_fails = function(bufnr, lnum, stderr, cron)
	local error_msg = stderr:match("Error: ([^\n]+)") or "Invalid cron expression"
	error_msg = error_msg:gsub("%s+$", "")

	local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
	local start_col, end_col = line:find(vim.pesc(cron))

	vim.diagnostic.set(ns, bufnr, {
		{
			lnum = lnum,
			col = start_col and (start_col - 1) or 0,
			end_col = end_col,
			severity = vim.diagnostic.severity.ERROR,
			message = error_msg,
			source = "cronex",
		},
	}, {})
	vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
		virt_text = { { "  Cron expression error", "DiagnosticError" } },
		virt_text_pos = "eol",
	})
end

local handle_timeout = function()
	vim.notify("CronExplained: Timeout")
end

local handle_no_output = function(bufnr, lnum)
	vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
		virt_text = { { "  Cron expression (no explanation)", "Comment" } },
		virt_text_pos = "eol",
	})
end

M.explain_with_virtual_text = function(cron, lnum, bufnr)
	-- Clear only this line's virtual text before showing anything new
	vim.api.nvim_buf_clear_namespace(bufnr, ns, lnum, lnum + 1)

	if cache[cron] then
		display_cron_explanation(bufnr, lnum, cache[cron])
		return
	end

	vim.system({ "cronstrue", cron }, { timeout = 1000, text = true }, function(obj)
		vim.schedule(function()
			if obj.code == 124 then
				handle_timeout()
				return
			end

			if obj.code ~= 0 then
				handle_cron_expression_fails(bufnr, lnum, obj.stderr, cron)
				return
			end

			if obj.stdout == "" then
				handle_no_output(bufnr, lnum)
				return
			end

			local explanation = obj.stdout:gsub("%s+$", "")
			cache[cron] = explanation
			display_cron_explanation(bufnr, lnum, explanation)
		end)
	end)
end

return M

-- lua/diagnostics.lua

local M = {}
local zen_diag = true -- Start in busy/zen mode

-- Store the original diagnostic configuration for restoration
local og_virt_text
local og_virt_line

-- This function toggles the diagnostics mode (Zen vs. Inline)
function M.toggle()
	zen_diag = not zen_diag
	vim.diagnostic.config({
		virtual_text = not zen_diag,
		virtual_lines = zen_diag and { current_line = true } or false,
		underline = true,
		update_in_insert = false,
	})
	vim.notify("Diagnostics: " .. (zen_diag and "Zen (virtual_lines)" or "Inline (virtual_text)"))
end

-- This function configures diagnostics, including autocommands and initial state
function M.setup()
	-- Ensure conflicting autocommands are cleared (we don’t want to override the toggle)
	pcall(vim.api.nvim_del_augroup_by_name, "diagnostic_only_virtlines")

	-- Save the original diagnostic config state
	og_virt_text = vim.diagnostic.config().virtual_text
	og_virt_line = vim.diagnostic.config().virtual_lines

	-- Default diagnostic configuration
	vim.diagnostic.config({
		virtual_text = true,
		virtual_lines = false, -- Start in "inline" mode
		underline = true,
		update_in_insert = false,
	})

	-- Autocommand to handle diagnostics dynamically based on cursor position (will respect toggle)
	vim.api.nvim_create_autocmd({ "CursorMoved", "DiagnosticChanged" }, {
		group = vim.api.nvim_create_augroup("diagnostic_only_virtlines", {}),
		callback = function()
			if og_virt_line == nil then
				og_virt_line = vim.diagnostic.config().virtual_lines
			end

			-- Ignore if virtual_lines.current_line is disabled
			if not (og_virt_line and og_virt_line.current_line) then
				if og_virt_text then
					vim.diagnostic.config({ virtual_text = og_virt_text })
					og_virt_text = nil
				end
				return
			end

			if og_virt_text == nil then
				og_virt_text = vim.diagnostic.config().virtual_text
			end

			local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

			if vim.tbl_isempty(vim.diagnostic.get(0, { lnum = lnum })) then
				vim.diagnostic.config({ virtual_text = og_virt_text })
			else
				vim.diagnostic.config({ virtual_text = false })
			end
		end,
	})

	-- Autocommand to redraw diagnostics when the mode changes
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = vim.api.nvim_create_augroup("diagnostic_redraw", {}),
		callback = function()
			pcall(vim.diagnostic.show)
		end,
	})
end

return M

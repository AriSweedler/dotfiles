vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client == nil then
			return
		end

		if client.server_capabilities.inlayHintProvider then
			vim.lsp.inlay_hint.enable(true, { bufnr = 0 })
		end
	end,
})

local inlay_hints_enabled = true

-- g: inlay hints
vim.keymap.set("n", "gih", function()
	inlay_hints_enabled = not inlay_hints_enabled
	vim.lsp.inlay_hint.enable(inlay_hints_enabled)
	vim.notify("Inlay hints " .. (inlay_hints_enabled and "enabled" or "disabled"))
end, { desc = "LSP: Toggle [I]nlay [H]ints" })
vim.api.nvim_set_hl(0, "LspInlayHint", { fg = "#008f40" })

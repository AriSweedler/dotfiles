local setup_inlay_hits = function(args)
	vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })

	-- Toggle and log
	vim.keymap.set("n", "gih", function()
		local is_enabled = vim.lsp.inlay_hint.is_enabled()
		vim.lsp.inlay_hint.enable(not is_enabled)
		vim.notify("Inlay hints " .. (is_enabled and "enabled" or "disabled"))
	end, { desc = "LSP: Toggle [I]nlay [H]ints", buffer = args.buf })

	-- And nice dark green color
	vim.api.nvim_set_hl(0, "LspInlayHint", { fg = "#008f40" })
end

local lsp_attched_callback = function(args)
	local client = vim.lsp.get_client_by_id(args.data.client_id)
	if client == nil then
		return
	end

	-- Enable inlay hints if possible
	if client.server_capabilities.inlayHintProvider then
		setup_inlay_hits(args)
	end
end

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = lsp_attched_callback,
})

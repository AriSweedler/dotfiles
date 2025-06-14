for _, rtp in ipairs(vim.opt.rtp:get()) do
	local lsp_dir = rtp .. "/lsp"
	local files = vim.fn.globpath(lsp_dir, "*.lua", false, true)

	for _, file in ipairs(files) do
		local ls = file:match("lsp/(.+)%.lua")
		vim.lsp.enable(ls)
	end
end

-- Auto-enable all LSP configurations from lsp/ directories
for _, rtp in ipairs(vim.api.nvim_list_runtime_paths()) do
  local lsp_dir = rtp .. "/lsp"
  if vim.fn.isdirectory(lsp_dir) == 1 then
    local files = vim.fn.globpath(lsp_dir, "*.lua", false, true)
    for _, file in ipairs(files) do
      local ls = file:match("lsp/([^/]+)%.lua$")
      if ls then
        vim.lsp.enable(ls)
      end
    end
  end
end

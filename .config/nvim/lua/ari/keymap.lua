local M = {}

--- Register a normal-mode keymap that lazy-loads a built-in opt-in plugin on
--- first use. The first keypress runs `packadd`, invokes the command, then
--- rebinds the key to invoke the command directly (skipping packadd on
--- subsequent presses).
---
--- @param opts table
--- @field key string Normal-mode lhs (e.g. "<Leader>U")
--- @field packadd string Name passed to `:packadd` (e.g. "nvim.undotree")
--- @field cmd function Command to run after loading (e.g. vim.cmd.UndotreeToggle)
--- @field desc string Keymap description shown in `:map` output
function M.lazyload(opts)
	local desc = opts.desc
	vim.keymap.set("n", opts.key, function()
		vim.cmd("packadd " .. opts.packadd)
		opts.cmd()
		vim.keymap.set("n", opts.key, opts.cmd, { desc = desc })
	end, { desc = desc })
end

return M

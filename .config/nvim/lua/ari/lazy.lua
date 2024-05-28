-- Install the setup manager 'Lazy' if needed.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"--branch=stable",
		lazyrepo,
		lazypath,
	})
end

-- Add it to runtime path
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
	defaults = { lazy = true },
	checker = { enabled = true },
})

-- If there are updates to be had, then update
vim.api.nvim_create_autocmd("VimEnter", {
	group = vim.api.nvim_create_augroup("lazyvim_autoupdate", { clear = true }),
	callback = function()
		if require("lazy.status").has_updates then
			require("lazy").update({ show = false })
		end
	end,
})

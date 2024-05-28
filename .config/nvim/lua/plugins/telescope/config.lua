-- Enable telescope fzf native, if installed
pcall(require("telescope").load_extension, "fzf")
pcall(require("telescope").load_extension, "ui-select")

require("plugins.telescope.files")
require("plugins.telescope.search")
require("plugins.telescope.fun")
require("plugins.telescope.lsp")

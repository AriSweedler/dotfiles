vim.o.textwidth = 98
vim.o.colorcolumn = "+1"

require('ari.operator').create_operator({
	name = "TFBoxOp",
	fn = require('ari.operator.tf').box,
	lhs = "<Leader>c",
	desc = "Terraform box comment",
	buffer = true,
})

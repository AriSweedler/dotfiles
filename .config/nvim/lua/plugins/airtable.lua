return {
  dir = vim.fn.expand("~/h/source/airtable.nvim"),
  name = "airtable.nvim",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    require('airtable').setup()
  end,
}

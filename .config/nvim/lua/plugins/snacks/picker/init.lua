local Snacks = require("snacks")

-- Is this necessary to get typing???
--
---@class snacks.picker.lsp.Loc: lsp.Location
---@field encoding string
---
---@alias snacks.picker.Pos {[1]:number, [2]:number}
---
---@alias snacks.picker.Highlight snacks.picker.Text|snacks.picker.Extmark
---
---@class snacks.picker.Item.preview
---@field text string text to show in the preview buffer
---@field ft? string optional filetype used tohighlight the preview buffer
---@field extmarks? snacks.picker.Extmark[] additional extmarks
---@field loc? boolean set to false to disable showing the item location in the preview
---
---@alias snacks.picker.Extmark vim.api.keyset.set_extmark|{col:number, row?:number, field?:string}
---
---@alias snacks.picker.Text {[1]:string, [2]:string?, virtual?:boolean, field?:string}
---
---@class snacks.picker.Item
---@field [string] any
---@field idx number
---@field score number
---@field frecency? number
---@field score_add? number
---@field score_mul? number
---@field source_id? number
---@field file? string
---@field text string
---@field pos? snacks.picker.Pos
---@field loc? snacks.picker.lsp.Loc
---@field end_pos? snacks.picker.Pos
---@field highlights? snacks.picker.Highlight[][]
---@field preview? snacks.picker.Item.preview
---@field resolve? fun(item:snacks.picker.Item)

local M = {}

--- @class GitFilesOpts
--- @field git_dir string
--- @field work_tree string
--- @field title string

--- @param opts GitFilesOpts
M.git_files = function(opts)
	return Snacks.picker({
		title = opts.title,
		finder = function()
			local cmd = {
				"git",
				"--git-dir=" .. opts.git_dir,
				"--work-tree=" .. opts.work_tree,
				"ls-tree",
				"-r",
				"--name-only",
				"HEAD",
			}
			local cmd_str = table.concat(cmd, " ")
			local filenames = vim.fn.systemlist(cmd_str)

			local items = {}
			for idx, filename in ipairs(filenames) do
				--- @type snacks.picker.Item
				local i = {
					file = filename,
					idx = idx,
					score = 100,
					text = filename,
				}
				table.insert(items, i)
			end

			return items
		end,
	})
end

return M

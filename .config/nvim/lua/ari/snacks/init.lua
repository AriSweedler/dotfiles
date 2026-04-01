local M = {}

-- =============================================================================
-- Bufmap utility
-- =============================================================================

--- Scope a group of picker keymaps under a shared description prefix and leader key.
---
--- The callback receives a `bufmap` function that creates normal-mode keymaps.
--- The final keymap LHS is `leader .. lhs` unless `opts.no_leader` is set.
--- The keymap description is `desc_prefix .. ": " .. desc`.
---
--- When `rhs` is a function, it is wrapped in a closure that forwards `opts.args`
--- so that picker arguments (title, cwd, win overrides, etc.) are passed through.
---
---@param desc_prefix string Prefix for keymap descriptions (e.g. "Snacks Picker")
---@param leader string Key prefix prepended to `lhs` unless `no_leader` is set (e.g. "<Leader>p")
---@param callback fun(bufmap: Bufmap) Function that receives the scoped `bufmap` and registers keymaps
---
---@alias Bufmap fun(lhs: string, rhs: string|function, desc?: string, opts?: BufmapOpts)
---
---@class BufmapOpts
---@field no_leader? boolean When truthy, use `lhs` as-is without prepending the leader
---@field enabled_fxn? boolean|fun():boolean Guard — when it evaluates to false, skip creating the keymap entirely
---@field args? table Arguments forwarded to the picker function (e.g. `{ cwd = "..." }`)
---@field keymapOpts? table Extra options passed to `vim.keymap.set` (merged under the generated `desc`)
---@field wik_min? table<string, string|fun(picker:snacks.Picker)> "With Input Key: Mode Insert Normal"
function M.block(desc_prefix, leader, callback)
	local function bufmap(lhs, rhs, desc, opts)
		opts = opts or {}
		desc = desc or (opts.args and opts.args.title) or "UNKNOWN"
		local keymapOpts = opts.keymapOpts or {}

		if opts.enabled_fxn then
			local enabled = opts.enabled_fxn
			if type(enabled) == "function" then
				enabled = enabled()
			end
			if not enabled then
				return
			end
		end

		if opts.no_leader == nil then
			lhs = leader .. lhs
		end

		-- Expand `wik_min` into nested args.win.input.keys with { "i", "n" } mode
		if opts.wik_min then
			local args = opts.args or {}
			opts.args = args
			local win = args.win or {}
			args.win = win
			local input = win.input or {}
			win.input = input
			input.keys = input.keys or {}
			local actions = args.actions or {}
			args.actions = actions

			for key, action in pairs(opts.wik_min) do
				local action_name = desc:lower():gsub("[^a-z]", "_")
				if type(action) == "string" then
					action_name = action
				elseif type(action) == "function" then
					actions[action_name] = action
				end
				if action_name then
					input.keys[key] = { action_name, mode = { "i", "n" } }
				end
			end
		end

		keymapOpts = vim.tbl_extend("force", keymapOpts, {
			desc = desc_prefix .. ": " .. desc,
		})

		if type(rhs) == "function" then
			local fn = rhs
			if opts.args then
				rhs = function() fn(opts.args) end
			else
				rhs = function() fn() end
			end
		end

		vim.keymap.set("n", lhs, rhs, keymapOpts)
	end

	callback(bufmap)
end

-- =============================================================================
-- Custom picker actions
-- =============================================================================

--- Open selected items in new tabs.
function M.action_tabedit(picker)
	local selections = picker:selected({ fallback = true })
	for _, item in ipairs(selections) do
		if not item.file then
			vim.notify("No file found for keymap: " .. item.text, vim.log.levels.ERROR)
			return
		end
		vim.cmd("tabedit " .. vim.fn.fnameescape(item.file))
		vim.api.nvim_win_set_cursor(0, item.pos)
	end
	picker:close()
end

--- Edit a register's contents in a floating scratch buffer.
function M.action_edit_register(picker)
	local selections = picker:selected({ fallback = true })
	local item = selections[1]
	if not item or not item.reg then
		vim.notify("No register selected", vim.log.levels.ERROR)
		return
	end
	picker:close()

	local reg = item.reg
	local contents = item.data or ""

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "register://" .. reg)
	local lines = vim.split(contents, "\n", { plain = true })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local width = math.min(80, vim.o.columns - 4)
	local height = math.min(math.max(#lines, 1) + 1, vim.o.lines - 4)
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " Register \"" .. reg .. "\" ",
		title_pos = "center",
	})

	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "text"

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			vim.fn.setreg(reg, table.concat(new_lines, "\n"))
			vim.bo[buf].modified = false
			vim.notify("Register \"" .. reg .. "\" updated")
		end,
	})
end

-- =============================================================================
-- Custom picker: git files from bare repo
-- =============================================================================

--- @class GitFilesOpts
--- @field git_dir string
--- @field work_tree string
--- @field title string

--- Pick files tracked by a bare git repo (e.g. dotfiles).
--- @param opts GitFilesOpts
function M.picker_git_files(opts)
	local Snacks = require("snacks")
	return Snacks.picker({
		title = opts.title,
		finder = function()
			local cmd = {
				"git",
				"--git-dir=" .. opts.git_dir,
				"--work-tree=" .. opts.work_tree,
				"ls",
				"-r",
				"--name-only",
			}
			local filenames = vim.fn.systemlist(table.concat(cmd, " "))

			local items = {}
			for idx, filename in ipairs(filenames) do
				table.insert(items, {
					file = opts.work_tree .. "/" .. filename,
					idx = idx,
					score = 100,
					text = filename,
				})
			end
			return items
		end,
	})
end

return M

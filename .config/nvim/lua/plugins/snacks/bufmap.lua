--- Utility module for creating normal-mode keymaps that open snacks pickers.
---
--- Provides `block(desc_prefix, leader, callback)` which scopes a group of
--- `bufmap()` calls under a shared description prefix and key leader. The
--- `bufmap` function is only accessible inside the callback, so the prefix and
--- leader can never be out of sync with the keymaps being created. Indentation
--- naturally groups related pickers together.
---
--- Usage from init.lua:
---   local bm = require("plugins.snacks.bufmap")
---   bm.block("Snacks Picker", "<Leader>p", function(bufmap)
---       bufmap("h", Snacks.picker.help, "Help pages")
---       bufmap("b", Snacks.picker.buffers, "Buffers")
---   end)
---
---@class BufmapModule
local M = {}

--- Check if a lua module can be required without error.
---@param module string The module name to check (e.g. "yaml_nvim")
---@return boolean ok True if `require(module)` succeeds
function M.can_require(module)
	local ok, _ = pcall(require, module)
	return ok
end

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
---@field wik_min? table<string, string|fun(picker:snacks.Picker)> "With Input Key: Mode Insert Normal" — keybindings active inside the picker's input window in both insert and normal mode. Keys are vim key notation (e.g. `"<C-D>"`). Values are either a built-in snacks action name (string) or a custom action function that receives the picker instance.
function M.block(desc_prefix, leader, callback)
	--- @param lhs string Key suffix appended to the leader (e.g. `"h"` becomes `<Leader>ph`)
	--- @param rhs string|function Picker function (e.g. `Snacks.picker.help`) or vim command string
	--- @param desc? string Human-readable description; falls back to `opts.args.title` or `"UNKNOWN"`
	--- @param opts? BufmapOpts Optional configuration table
	local function bufmap(lhs, rhs, desc, opts)
		desc = desc or opts.args.title or "UNKNOWN"
		opts = opts or {}
		local keymapOpts = opts.keymapOpts or {}

		-- Exit early if not enabled
		if opts.enabled_fxn then
			local enabled_verdict = true
			if type(opts.enabled_fxn) == "function" then
				enabled_verdict = opts.enabled_fxn()
			elseif type(opts.enabled_fxn) == "boolean" then
				enabled_verdict = opts.enabled_fxn
			end
			if not enabled_verdict then
				return
			end
		end

		if opts.no_leader == nil then
			lhs = leader .. lhs
		end

		-- Expand `wik_min` into nested args.win.input.keys with { "i", "n" } mode
		-- wik_min stands for: With Input Key: Mode Insert Normal
		if opts.wik_min then
			opts.args = opts.args or {}
			local args = opts.args
			args.win = args.win or {}
			args.win.input = args.win.input or {}
			args.win.input.keys = args.win.input.keys or {}
			args.actions = args.actions or {}

			for key, action in pairs(opts.wik_min) do
				local action_name = desc:lower():gsub("[^a-z]", "_")

				-- Use a built-in action or a user-supplied function
				if type(action) == "string" then
					action_name = action
				elseif type(action) == "function" then
					args.actions[action_name] = action
				end

				if action_name then
					args.win.input.keys[key] = {
						action_name,
						mode = { "i", "n" },
					}
				end
			end
		end

		-- Generate and extend opts with "desc"
		keymapOpts = vim.tbl_extend("force", keymapOpts, {
			desc = desc_prefix .. ": " .. desc,
		})

		-- if 'rhs' is a function, then create a closure to set the args
		if type(rhs) == "function" then
			local fn = rhs
			if opts.args then
				rhs = function()
					fn(opts.args)
				end
			else
				rhs = function()
					fn()
				end
			end
		end

		vim.keymap.set("n", lhs, rhs, keymapOpts)
	end

	callback(bufmap)
end

return M

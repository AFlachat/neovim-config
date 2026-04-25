-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Width-resize that also works on floating windows (e.g. Snacks explorer).
-- Overrides LazyVim's <C-Left>/<C-Right> which use `:vertical resize` (splits only).
local STEP = 4
local MIN_W = 10

local function nudge_width(delta)
  local win = vim.api.nvim_get_current_win()
  local cur = vim.api.nvim_win_get_width(win)
  vim.api.nvim_win_set_width(win, math.max(MIN_W, cur + delta))
end

vim.keymap.set("n", "<leader><Right>", function() nudge_width(STEP) end,  { desc = "Increase Window Width" })
vim.keymap.set("n", "<leader><Left>",  function() nudge_width(-STEP) end, { desc = "Decrease Window Width" })

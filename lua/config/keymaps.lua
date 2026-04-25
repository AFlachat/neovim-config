-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Width/height resize that also works on floating windows (e.g. Snacks explorer).
-- Vim's `:vertical resize` and `:resize` are splits-only.
local STEP_W = 4
local STEP_H = 2
local MIN_W = 10
local MIN_H = 3

local function nudge_width(delta)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, math.max(MIN_W, vim.api.nvim_win_get_width(win) + delta))
end

local function nudge_height(delta)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(win, math.max(MIN_H, vim.api.nvim_win_get_height(win) + delta))
end

vim.keymap.set("n", "<leader><Right>", function() nudge_width(STEP_W)  end, { desc = "Increase Window Width" })
vim.keymap.set("n", "<leader><Left>",  function() nudge_width(-STEP_W) end, { desc = "Decrease Window Width" })
vim.keymap.set("n", "<leader><Up>",    function() nudge_height(STEP_H) end, { desc = "Increase Window Height" })
vim.keymap.set("n", "<leader><Down>",  function() nudge_height(-STEP_H) end, { desc = "Decrease Window Height" })

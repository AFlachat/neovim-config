local M = {}

---Tracks the single active logs split buffer so a second invocation can close the first.
---@type integer|nil
local log_buf = nil

---Open a horizontal split below, run `cmd` (argv list) in a terminal buffer.
---Any previously-opened logs split is closed first.
---@param cmd string[]
function M.open_split(cmd)
  if log_buf and vim.api.nvim_buf_is_valid(log_buf) then
    vim.api.nvim_buf_delete(log_buf, { force = true })
  end

  vim.cmd("botright 15split")
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  log_buf = buf

  vim.bo[buf].bufhidden = "wipe"
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"

  vim.fn.termopen(cmd)

  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set({ "n", "t" }, "q", "<cmd>bdelete!<cr>", opts)
  vim.keymap.set({ "n", "t" }, "<Esc>", "<cmd>bdelete!<cr>", opts)
end

return M

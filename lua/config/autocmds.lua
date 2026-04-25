-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- Open a Snacks terminal at the bottom on startup, leaving focus on the editor.
-- Toggle later with <C-/> (LazyVim default) — same persistent terminal is focused/hidden.
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("docker_default_bottom_term", { clear = true }),
  callback = function()
    if #vim.api.nvim_list_uis() == 0 then return end -- skip headless
    Snacks.terminal.open(nil, {
      win = { position = "bottom", height = 0.20 },
      start_insert = false,
      auto_insert = false,
    })
    vim.schedule(function() vim.cmd("wincmd p") end)
  end,
})

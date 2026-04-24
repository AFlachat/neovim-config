local M = {}

local PREFIX = "<leader>r"
local GROUP_NAME = "Run"
local GROUP_ICON = "󰑮"

local function run_script(cmd)
  Snacks.terminal(cmd, {
    win = {
      position = "float",
      border = "rounded",
      title = " " .. cmd .. " ",
      title_pos = "center",
      width = 0.8,
      height = 0.8,
    },
    auto_close = true,
    interactive = true,
  })
end

function M.setup(scripts)
  for _, script in ipairs(scripts or {}) do
    vim.keymap.set("n", PREFIX .. script.key, function()
      run_script(script.path)
    end, { desc = script.desc, silent = true })
  end

  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add({ { PREFIX, group = GROUP_NAME, icon = GROUP_ICON } })
  end
end

return M

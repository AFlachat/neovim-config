return {
  {
    "folke/snacks.nvim",
    ---@type snacks.Config
    opts = {
      picker = {
        sources = {
          explorer = {
            layout = {
              preset = "sidebar",
              preview = false,
              layout = { width = 40 }, -- columns, or use <1 for relative (e.g. 0.2)
            },
          },
        },
      },
    }
  }
}
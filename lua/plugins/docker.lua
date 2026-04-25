return {
  {
    dir = vim.fn.stdpath("config"),
    name = "docker.nvim",
    dependencies = { "folke/snacks.nvim" },
    event = "VeryLazy",
    keys = {
      { "<leader>C", function() require("docker").open() end, desc = "Docker" },
    },
    config = function()
      require("docker").setup({})
    end,
  },
}

return {
  {
    "h4ckm1n-dev/kube-utils-nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    lazy = true,
    event = "VeryLazy",
    config = true,
    keys = {
      { "<leader>khT", "<cmd>HelmDryRun<CR>",                     desc = "Helm DryRun Buffer" },
      { "<leader>khb", "<cmd>HelmDependencyBuildFromBuffer<CR>",  desc = "Helm Dependency Build" },
      { "<leader>khd", "<cmd>HelmDeployFromBuffer<CR>",           desc = "Helm Deploy Buffer to Context" },
      { "<leader>khr", "<cmd>RemoveDeployment<CR>",               desc = "Helm Remove Deployment From Buffer" },
      { "<leader>kht", "<cmd>HelmTemplateFromBuffer<CR>",         desc = "Helm Template From Buffer" },
      { "<leader>khu", "<cmd>HelmDependencyUpdateFromBuffer<CR>", desc = "Helm Dependency Update" },
      { "<leader>kkC", "<cmd>SelectSplitCRD<CR>",                 desc = "Download CRD Split" },
      { "<leader>kkD", "<cmd>DeleteNamespace<CR>",                desc = "Kubectl Delete Namespace" },
      { "<leader>kkK", "<cmd>OpenK9s<CR>",                        desc = "Open K9s" },
      { "<leader>kka", "<cmd>KubectlApplyFromBuffer<CR>",         desc = "Kubectl Apply From Buffer" },
      { "<leader>kkc", "<cmd>SelectCRD<CR>",                      desc = "Download CRD" },
      { "<leader>kkk", "<cmd>OpenK9sSplit<CR>",                   desc = "Split View K9s" },
      { "<leader>kkl", "<cmd>ToggleYamlHelm<CR>",                 desc = "Toggle YAML/Helm" },
      { "<leader>klf", "<cmd>JsonFormatLogs<CR>",                 desc = "Format JSON" },
      { "<leader>klv", "<cmd>ViewPodLogs<CR>",                    desc = "View Pod Logs" },
    }
  },
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>k",   group = "Kubernetes", mode = { "n", "v" }, icon = "󱃾" },
        { "<leader>kh",  group = "Helm",                            icon = "⎈" },
        { "<leader>kk",  group = "Kubectl",                         icon = "󱃾" },
        { "<leader>kl",  group = "Logs" },
      },
    },
  }
}

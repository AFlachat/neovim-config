return {
  {
    'nvim-flutter/flutter-tools.nvim',
    lazy = false,
    dependencies = {
      'nvim-lua/plenary.nvim',
      'stevearc/dressing.nvim',
    },
    config = true,
    keys = {
      { "<leader>Fr", "<cmd>FlutterRun<cr>",             desc = "Flutter Run" },
      { "<leader>Fq", "<cmd>FlutterQuit<cr>",            desc = "Flutter Quit" },
      { "<leader>FR", "<cmd>FlutterRestart<cr>",         desc = "Flutter Restart (hot)" },
      { "<leader>Fh", "<cmd>FlutterReload<cr>",          desc = "Flutter Hot Reload" },
      { "<leader>Fd", "<cmd>FlutterDevices<cr>",         desc = "Flutter Devices" },
      { "<leader>Fe", "<cmd>FlutterEmulators<cr>",       desc = "Flutter Emulators" },
      { "<leader>Fo", "<cmd>FlutterOutlineToggle<cr>",   desc = "Flutter Outline" },
      { "<leader>Fl", "<cmd>FlutterLogClear<cr>",        desc = "Flutter Clear Log" },
      { "<leader>FL", "<cmd>FlutterLogToggle<cr>",       desc = "Flutter Toggle Log" },
      { "<leader>Fp", "<cmd>FlutterPubGet<cr>",          desc = "Flutter Pub Get" },
      { "<leader>Fu", "<cmd>FlutterPubUpgrade<cr>",      desc = "Flutter Pub Upgrade" },
      { "<leader>Fs", "<cmd>FlutterSuper<cr>",           desc = "Go to Super" },
      { "<leader>FD", "<cmd>FlutterDebug<cr>",           desc = "Flutter Debug" },
      { "<leader>Fv", "<cmd>FlutterDevTools<cr>",        desc = "Open DevTools" },
      { "<leader>FV", "<cmd>FlutterCopyProfilerUrl<cr>", desc = "Copy Profiler URL" },
    },
  },
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>F",  group = "Flutter", mode = { "n", "v" } },
      },
    },
  }
}

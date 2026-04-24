# 💤 Neovim Config

My personal Neovim configuration, built on top of [LazyVim](https://github.com/LazyVim/LazyVim).

## Requirements

On top of [LazyVim's own requirements](https://www.lazyvim.org/installation), the custom plugins here need:

- `claude` CLI on `$PATH` — for [claudecode.nvim](https://github.com/coder/claudecode.nvim)
- Flutter & Dart SDKs — for [flutter-tools.nvim](https://github.com/nvim-flutter/flutter-tools.nvim)
- `magick` CLI (ImageMagick 7) — for [image.nvim](https://github.com/3rd/image.nvim)
- `sqlit` CLI on `$PATH` — for [sqlit.nvim](https://github.com/Maxteabag/sqlit.nvim)
- `k9s` CLI on `$PATH` — for [kube-utils-nvim](https://github.com/h4ckm1n-dev/kube-utils-nvim)

## Installation

Back up any existing config first, then clone:

```sh
# back up existing config
mv ~/.config/nvim{,.bak}
mv ~/.local/share/nvim{,.bak}
mv ~/.local/state/nvim{,.bak}
mv ~/.cache/nvim{,.bak}

# install
git clone https://github.com/AFlachat/nvim ~/.config/nvim
nvim
```

LazyVim will bootstrap `lazy.nvim` and install all plugins on first launch.

## Layout

```
.
├── init.lua               # entry point, bootstraps LazyVim
├── lazyvim.json           # enabled LazyVim "extras"
├── lua/
│   ├── config/            # LazyVim config overrides (options, keymaps, autocmds, lazy)
│   ├── plugins/           # custom plugin specs
│   └── project_scripts/   # helper for per-project <leader>r… scripts
└── stylua.toml
```

## LazyVim extras enabled

AI: `claudecode` · Coding: `nvim-cmp` · Editor: `outline`, `telescope` · Utils: `dot`, `gitui`, `rest`, `vscode`

Languages: Ansible, Dart, Docker, Git, Go, Helm, JSON, Markdown, SQL, Tailwind, Terraform, TypeScript, YAML.

## Custom plugins

- **[claudecode.nvim](https://github.com/coder/claudecode.nvim)** — Claude Code integration, right-split terminal, vertical diffs.
- **[flutter-tools.nvim](https://github.com/nvim-flutter/flutter-tools.nvim)** — Flutter workflow under `<leader>F` (run, quit, hot reload/restart, devices, emulators, outline, logs, pub get/upgrade, DevTools, super).
- **[sqlit.nvim](https://github.com/Maxteabag/sqlit.nvim)** — lightweight SQLite UI on `<leader>D`.
- **[image.nvim](https://github.com/3rd/image.nvim)** — inline image rendering (uses `magick` CLI).
- **[snacks.nvim](https://github.com/folke/snacks.nvim)** — explorer tuned to a 40-column sidebar without preview.

## Project-local scripts

`lua/project_scripts` exposes a small helper to register per-project scripts under `<leader>r`. Combined with `vim.o.exrc = true` (enabled in `lua/config/options.lua`), each project can ship its own `.nvim.lua`:

```lua
-- <project>/.nvim.lua
require("project_scripts").setup({
  { key = "t", path = "./scripts/test.sh",  desc = "Run tests"  },
  { key = "d", path = "./scripts/dev.sh",   desc = "Dev server" },
})
```

Each entry binds `<leader>r<key>` to run the script in a floating Snacks terminal, and registers the `Run` group in which-key.

> Neovim will prompt to trust `.nvim.lua` the first time it loads.

## Useful keymaps

| Keys          | Action                         |
| ------------- | ------------------------------ |
| `<leader>F*`  | Flutter commands (see above)   |
| `<leader>D`   | Open SQLite explorer           |
| `<leader>r*`  | Project scripts (per-project)  |

Everything else is stock LazyVim — see its [keymap reference](https://www.lazyvim.org/keymaps).

## License

[Apache-2.0](./LICENSE)

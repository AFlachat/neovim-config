return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      -- Server Configuration
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "info", -- "trace", "debug", "info", "warn", "error"
      terminal_cmd = nil, -- Custom terminal command (default: "claude")
                          -- For local installations: "~/.claude/local/claude"
                          -- For native binary: use output from 'which claude'
  
      -- Send/Focus Behavior
      -- When true, successful sends will focus the Claude terminal if already connected
      focus_after_send = false,
  
      -- Selection Tracking
      track_selection = true,
      visual_demotion_delay_ms = 50,
  
      -- Terminal Configuration
      terminal = {
        split_side = "right", -- "left" or "right"
        split_width_percentage = 0.25,
        provider = "auto", -- "auto", "snacks", "native", "external", "none", or custom provider table
        auto_close = true,
        snacks_win_opts = {}, -- Opts to pass to `Snacks.terminal.open()` - see Floating Window section below
  
        -- Provider-specific options
        provider_opts = {
          -- Command for external terminal provider. Can be:
          -- 1. String with %s placeholder: "alacritty -e %s" (backward compatible)
          -- 2. String with two %s placeholders: "alacritty --working-directory %s -e %s" (cwd, command)
          -- 3. Function returning command: function(cmd, env) return "alacritty -e " .. cmd end
          external_terminal_cmd = nil,
        },
      },
  
      -- Diff Integration
      diff_opts = {
        layout = "vertical", -- "vertical" or "horizontal"
        open_in_new_tab = false,
        keep_terminal_focus = false, -- If true, moves focus back to terminal after diff opens
        hide_terminal_in_new_tab = false,
        -- on_new_file_reject = "keep_empty", -- "keep_empty" or "close_window"
  
        -- Legacy aliases (still supported):
        -- vertical_split = true,
        -- open_in_current_tab = true,
      },
    }
  }
}
local M = {}

local DEFAULTS = {
  key = "<leader>C",
  shell = "sh",
  confirm_destructive = true,
  log_tail = 200,
}

M.config = {}

local RESOURCES = {
  { name = "Containers", icon = "󰡨", module = "docker.containers" },
  { name = "Images",     icon = "",  module = "docker.images" },
  { name = "Volumes",    icon = "",  module = "docker.volumes" },
  { name = "Networks",   icon = "󰛳", module = "docker.networks" },
  { name = "Compose",    icon = "",  module = "docker.compose" },
}

local GLOBAL_FOOTER_KEYS = {
  { "R",   "Refresh" },
  { "q",   "Close" },
}

local SUBVIEW_FOOTER_EXTRA = {
  { "<BS>", "Back" },
}

local function ensure_non_empty(items, empty_text)
  if #items == 0 then
    return { { text = empty_text, name = empty_text, _placeholder = true } }
  end
  return items
end

---Collect union of all shortcut keys used by any resource (so we can register
---one dispatching action per key up front).
local function all_shortcut_keys()
  local seen = {}
  for _, r in ipairs(RESOURCES) do
    local mod = require(r.module)
    for _, sc in ipairs(mod.shortcuts or {}) do
      seen[sc.key] = true
    end
  end
  return seen
end

local RESOURCE_SIDEBAR_WIDTH = 24

local function base_layout(initial_footer)
  return {
    layout = {
      box = "horizontal",
      width = 0.85,
      min_width = 100,
      height = 0.8,
      {
        win = "preview",
        title = " Resources [p] ",
        title_pos = "center",
        border = true,
        width = RESOURCE_SIDEBAR_WIDTH,
      },
      {
        box = "vertical",
        border = true,
        title = "{title} [l]",
        footer = initial_footer,
        footer_pos = "center",
        { win = "input", height = 1, border = "bottom" },
        { win = "list",  border = "none" },
      },
    },
  }
end

---@param opts? { resource?: integer }
function M.open(opts)
  opts = opts or {}
  if vim.fn.executable("docker") == 0 then
    vim.notify("docker: CLI not found on $PATH", vim.log.levels.WARN)
    return
  end

  local ui = require("docker.ui")

  local current_res = opts.resource or 1
  ---A subview overrides the resource's default view (items, format, shortcuts, title).
  ---Only one level of nesting (e.g., Compose projects → services).
  ---@type nil | { title: string, produce: fun(cb), format: fun(item), shortcuts: table[], auto_refresh_ms?: integer, scroll_to_bottom?: boolean }
  local subview = nil
  local items_cache = {}
  local items_err = nil
  local subview_timer = nil ---@type uv_timer_t|nil
  local picker

  local function current_produce()
    return (subview and subview.produce) or require(RESOURCES[current_res].module).produce
  end

  local function current_format()
    return (subview and subview.format) or require(RESOURCES[current_res].module).format
  end

  local function current_shortcuts()
    return (subview and subview.shortcuts) or require(RESOURCES[current_res].module).shortcuts or {}
  end

  local function current_title()
    if subview then
      return " " .. subview.title .. " "
    end
    return " " .. RESOURCES[current_res].name .. " "
  end

  local function placeholder_text()
    if items_err == "Docker daemon not running" then
      return "(docker daemon unreachable)"
    elseif items_err then
      return "(error: " .. items_err:match("^(.-)\n") .. ")"
    elseif subview then
      return "(empty)"
    else
      return "(no " .. RESOURCES[current_res].name:lower() .. ")"
    end
  end

  local function update_title()
    if not picker or picker.closed then return end
    picker.title = current_title()
    pcall(function() picker:update_titles() end)
  end

  local function update_footer()
    if not picker or picker.closed then return end
    local globals = subview
      and vim.list_extend(vim.deepcopy(SUBVIEW_FOOTER_EXTRA), GLOBAL_FOOTER_KEYS)
      or GLOBAL_FOOTER_KEYS
    local footer = ui.shortcuts_to_footer(current_shortcuts(), globals)
    local box_win = picker.layout and picker.layout.box_wins and picker.layout.box_wins[2]
    if not box_win then return end
    box_win.opts.footer = footer
    pcall(function() box_win:update() end)
  end

  local function format(item, _)
    if item._placeholder then
      return { { item.text, "Comment" } }
    end
    return current_format()(item)
  end

  local function preview(ctx)
    ctx.preview:reset()
    local lines = {}
    for i, r in ipairs(RESOURCES) do
      local marker = (i == current_res) and "▶ " or "  "
      lines[#lines + 1] = marker .. r.name
    end
    ctx.preview:set_lines(lines)
    local ns = vim.api.nvim_create_namespace("docker_resources_sidebar")
    vim.api.nvim_buf_clear_namespace(ctx.buf, ns, 0, -1)
    vim.api.nvim_buf_set_extmark(ctx.buf, ns, current_res - 1, 0, {
      end_col = #lines[current_res],
      hl_group = "SnacksPickerLabel",
    })
  end

  local function refresh_preview()
    if picker and not picker.closed then
      pcall(function() picker:show_preview() end)
    end
  end

  local function set_items(items)
    picker.opts.items = items
    pcall(function() picker:find({ refresh = true }) end)
  end

  local function sync_load()
    local done, items, err = false, {}, nil
    current_produce()(function(i, e)
      items, err = i or {}, e
      done = true
    end)
    vim.wait(3000, function() return done end, 20)
    items_cache = items
    items_err = err
  end

  local function items_or_placeholder()
    return ensure_non_empty(items_cache, placeholder_text())
  end

  local function reload()
    sync_load()
    if picker and not picker.closed then
      update_title()
      update_footer()
      set_items(items_or_placeholder())
    end
  end

  local function async_refresh()
    current_produce()(vim.schedule_wrap(function(items, err)
      items_cache = items or {}
      items_err = err
      if picker and not picker.closed then
        set_items(items_or_placeholder())
      end
    end))
  end

  local function stop_subview_timer()
    if subview_timer and not subview_timer:is_closing() then
      subview_timer:stop()
      subview_timer:close()
    end
    subview_timer = nil
  end

  local function scroll_list_to_bottom()
    if not picker or picker.closed or not picker.list then return end
    vim.schedule(function()
      pcall(function()
        local n = picker.list:count()
        if n > 0 then picker.list:move(n, true) end
      end)
    end)
  end

  -- Context passed to each shortcut fn.
  local ctx = {}
  ctx.refresh = async_refresh
  ctx.open_subview = function(spec)
    stop_subview_timer()
    subview = spec
    reload()
    if spec.scroll_to_bottom then
      scroll_list_to_bottom()
    end
    if spec.auto_refresh_ms and spec.auto_refresh_ms > 0 then
      subview_timer = vim.uv.new_timer()
      subview_timer:start(spec.auto_refresh_ms, spec.auto_refresh_ms, vim.schedule_wrap(function()
        if not picker or picker.closed or subview ~= spec then
          stop_subview_timer()
          return
        end
        spec.produce(function(items)
          if not picker or picker.closed or subview ~= spec then return end
          items_cache = items or {}
          set_items(items_or_placeholder())
          if spec.scroll_to_bottom then scroll_list_to_bottom() end
        end)
      end))
    end
  end
  ctx.close_subview = function()
    if subview then
      stop_subview_timer()
      subview = nil
      reload()
    end
  end
  ---Open a (non-terminal) buffer in a floating window stacked exactly over the
  ---list pane. Closed by `q` or `<Esc>` on the overlay buffer.
  ---@param buf integer
  ctx.swap_list_with_buffer = function(buf)
    if not picker or picker.closed then return end
    local list_win = picker.list and picker.list.win and picker.list.win.win
    if not list_win or not vim.api.nvim_win_is_valid(list_win) then return end

    local pos = vim.api.nvim_win_get_position(list_win)
    local width = vim.api.nvim_win_get_width(list_win)
    local height = vim.api.nvim_win_get_height(list_win)

    local list_zindex
    pcall(function() list_zindex = vim.api.nvim_win_get_config(list_win).zindex end)
    local overlay_win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = pos[1],
      col = pos[2],
      width = width,
      height = height,
      style = "minimal",
      zindex = (list_zindex or 50) + 5,
    })
    vim.keymap.set("n", "q",     "<cmd>close<cr>", { buffer = buf, silent = true })
    vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
    return overlay_win
  end

  ---Open a terminal in a floating window stacked exactly over the list pane.
  ---When the terminal process exits, close the float — the picker stays intact
  ---underneath and is revealed.
  ---@param cmd string[]
  ctx.swap_list_with_terminal = function(cmd)
    if not picker or picker.closed then return end
    local list_win = picker.list and picker.list.win and picker.list.win.win
    if not list_win or not vim.api.nvim_win_is_valid(list_win) then return end

    local pos = vim.api.nvim_win_get_position(list_win)
    local width = vim.api.nvim_win_get_width(list_win)
    local height = vim.api.nvim_win_get_height(list_win)

    local term_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[term_buf].bufhidden = "wipe"

    local list_zindex
    pcall(function()
      list_zindex = vim.api.nvim_win_get_config(list_win).zindex
    end)
    local term_win = vim.api.nvim_open_win(term_buf, true, {
      relative = "editor",
      row = pos[1],
      col = pos[2],
      width = width,
      height = height,
      style = "minimal",
      zindex = (list_zindex or 50) + 5,
    })

    vim.fn.termopen(cmd, {
      on_exit = vim.schedule_wrap(function()
        if vim.api.nvim_win_is_valid(term_win) then
          pcall(vim.api.nvim_win_close, term_win, true)
        end
      end),
    })
    vim.cmd("startinsert")
  end

  local function switch_resource(new_res)
    if new_res == current_res and not subview then return end
    current_res = new_res
    subview = nil
    reload()
    refresh_preview()
  end

  -- Initial sync load.
  sync_load()
  local initial_items = items_or_placeholder()
  local initial_footer = ui.shortcuts_to_footer(current_shortcuts(), GLOBAL_FOOTER_KEYS)

  -- Build action table: one action per shortcut key (dispatched at runtime).
  local actions = {
    focus_resources = function(p) p:focus("preview") end,
    focus_list = function(p)
      if subview then
        ctx.close_subview()
      else
        p:focus("list")
      end
    end,
    focus_input = function(p) p:focus("input") end,
    docker_refresh = function() async_refresh() end,
    back_subview = function() ctx.close_subview() end,
    resources_select = function(p)
      local row = vim.api.nvim_win_get_cursor(0)[1]
      if row < 1 or row > #RESOURCES then return end
      switch_resource(row)
      p:focus("list")
    end,
  }
  local list_keymaps = {
    ["p"]    = { "focus_resources", desc = "Focus Resources" },
    ["R"]    = { "docker_refresh",  desc = "Refresh" },
    ["<BS>"] = { "back_subview",    desc = "Back" },
    ["/"]    = { "focus_input",     desc = "Search" },
  }
  for key in pairs(all_shortcut_keys()) do
    if key ~= "p" and key ~= "R" and key ~= "l" and key ~= "q" and key ~= "/" then
      local action_name = "docker_sc_" .. key
      actions[action_name] = function(p)
        local item = p:current()
        if not item or item._placeholder then return end
        for _, sc in ipairs(current_shortcuts()) do
          if sc.key == key then
            sc.fn(item, ctx)
            return
          end
        end
      end
      list_keymaps[key] = { action_name, desc = "shortcut " .. key }
    end
  end

  picker = Snacks.picker.pick({
    title = current_title(),
    items = initial_items,
    layout = base_layout(initial_footer),
    format = format,
    preview = preview,
    sort = { fields = { "idx" } },
    focus = "list",

    actions = actions,

    win = {
      input = {
        keys = {
          ["<Esc>"] = { "focus_list", mode = { "n", "i" }, desc = "Back to list" },
          ["<CR>"]  = { "focus_list", mode = { "n", "i" }, desc = "Back to list" },
        },
      },
      list = { keys = list_keymaps },
      preview = {
        keys = {
          ["<CR>"] = { "resources_select", desc = "Select resource" },
          ["l"]    = { "focus_list",       desc = "Focus List" },
          ["q"]    = "close",
          ["<Esc>"] = "close",
        },
      },
    },

    confirm = function(_, item)
      if not item or item._placeholder then return end
      if subview and subview.on_select then
        subview.on_select(item, ctx)
      end
    end,
    on_close = function() stop_subview_timer() end,
  })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", DEFAULTS, opts or {})

  if M.config.key then
    vim.keymap.set("n", M.config.key, function() M.open() end, { desc = "Docker" })
  end

  vim.api.nvim_create_user_command("Docker",           function() M.open() end, {})
  vim.api.nvim_create_user_command("DockerContainers", function() M.open({ resource = 1 }) end, {})
  vim.api.nvim_create_user_command("DockerImages",     function() M.open({ resource = 2 }) end, {})
  vim.api.nvim_create_user_command("DockerVolumes",    function() M.open({ resource = 3 }) end, {})
  vim.api.nvim_create_user_command("DockerNetworks",   function() M.open({ resource = 4 }) end, {})
  vim.api.nvim_create_user_command("DockerCompose",    function() M.open({ resource = 5 }) end, {})

  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add({ { M.config.key, group = "Docker", icon = "󰡨" } })
  end
end

return M

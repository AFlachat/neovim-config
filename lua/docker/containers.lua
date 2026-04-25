local cli = require("docker.cli")
local ui = require("docker.ui")
local terminal = require("docker.terminal")

local M = {}

---`docker ps -a --format '{{json .}}'` fields: Names, Image, ID, State, Status,
---Ports, CreatedAt, RunningFor.
---@param raw table
---@return table
local function make_item(raw)
  local name = raw.Names or raw.Name or raw.ID or "?"
  local state = raw.State or raw.Status or "?"
  return {
    text = (name .. " " .. (raw.Image or "")),
    name = name,
    id = raw.ID,
    state = state,
    image = raw.Image or "",
    ports = raw.Ports or "",
    created = raw.RunningFor or raw.CreatedAt or "",
    raw = raw,
  }
end

---@param item table
function M.format(item)
  local state_hl = (item.state == "running") and "DiagnosticOk" or "Comment"
  return {
    { string.format("%-9s ", item.state:sub(1, 9)), state_hl },
    { string.format("%-24s ", item.name:sub(1, 24)), "SnacksPickerLabel" },
    { string.format("%-32s ", item.image:sub(1, 32)), "SnacksPickerDir" },
    { item.ports, "Comment" },
  }
end

---@param item table
local function action_logs(item)
  local cfg = require("docker").config
  terminal.open_split({
    "docker", "logs", "-f", "--tail", tostring(cfg.log_tail), item.id,
  })
end

---@param item table
---@param ctx table
local function action_shell(item, ctx)
  local cfg = require("docker").config
  ctx.swap_list_with_terminal({ "docker", "exec", "-it", item.id, cfg.shell })
end

local function get_workdir(container_id)
  local r = cli.run_sync({ "inspect", "--format", "{{.Config.WorkingDir}}", container_id })
  if not r.ok then return "/" end
  local wd = (r.stdout or ""):gsub("%s+$", "")
  if wd == "" then wd = "/" end
  return wd
end

local function parent_path(p)
  if p == "/" or p == "" then return "/" end
  local stripped = p:gsub("/+$", "")
  local parent = stripped:match("^(.*)/[^/]+$") or "/"
  if parent == "" then parent = "/" end
  return parent
end

local function join_path(dir, name)
  if dir:sub(-1) == "/" then
    return dir .. name
  end
  return dir .. "/" .. name
end

local function preview_file(item, ctx)
  local r = cli.run_sync({ "exec", item.container_id, "cat", item.path })
  if not r.ok then
    vim.notify(r.stderr ~= "" and r.stderr or "cat failed", vim.log.levels.ERROR, { title = "Docker" })
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(r.stdout or "", "\n", { plain = true }))
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  local ext = item.name:match("%.([%w]+)$")
  if ext then
    pcall(function() vim.bo[buf].filetype = ext end)
  end
  ctx.swap_list_with_buffer(buf)
end

local STATS_HISTORY_MAX = 40
local STATS_REFRESH_MS = 2000

local function make_stats_subview(container_id, container_name)
  local hist = { cpu = {}, mem = {} }

  local function push(t, v)
    table.insert(t, v)
    if #t > STATS_HISTORY_MAX then table.remove(t, 1) end
  end

  return {
    title = "Stats: " .. container_name,
    produce = function(cb)
      local r = cli.run_sync({
        "stats", "--no-stream", "--format", "{{json .}}", container_id,
      })
      if not r.ok then
        cb({ { text = "(stats failed)", _placeholder = true, name = "" } })
        return
      end
      local ok, s = pcall(vim.json.decode, vim.trim(r.stdout or ""))
      if not ok or type(s) ~= "table" then
        cb({ { text = "(parse failed)", _placeholder = true, name = "" } })
        return
      end

      local cpu = tonumber(((s.CPUPerc or "0%"):gsub("%%", ""))) or 0
      local mem = tonumber(((s.MemPerc or "0%"):gsub("%%", ""))) or 0
      push(hist.cpu, cpu)
      push(hist.mem, mem)

      cb({
        {
          text = "CPU", idx = 1,
          _label = "CPU",
          _value = string.format("%6.2f %%", cpu),
          _spark = ui.sparkline(hist.cpu, 100),
          _spark_hl = "DiagnosticInfo",
        },
        {
          text = "Memory", idx = 2,
          _label = "Memory",
          _value = string.format("%6.2f %%   %s", mem, s.MemUsage or ""),
          _spark = ui.sparkline(hist.mem, 100),
          _spark_hl = "DiagnosticWarn",
        },
        { text = "Net I/O",   idx = 3, _label = "Net I/O",   _value = s.NetIO   or "" },
        { text = "Block I/O", idx = 4, _label = "Block I/O", _value = s.BlockIO or "" },
        { text = "PIDs",      idx = 5, _label = "PIDs",      _value = tostring(s.PIDs or "") },
        {
          text = "samples", idx = 6,
          _label = "samples",
          _value = string.format("%d/%d (every %ds)", #hist.cpu, STATS_HISTORY_MAX, STATS_REFRESH_MS / 1000),
          _value_hl = "Comment",
        },
      })
    end,
    format = function(it)
      if it._placeholder then
        return { { it.text, "Comment" } }
      end
      local segs = {
        { string.format("%-10s ", it._label), "SnacksPickerLabel" },
        { string.format("%-32s ", it._value or ""), it._value_hl or "Number" },
      }
      if it._spark and it._spark ~= "" then
        segs[#segs + 1] = { it._spark, it._spark_hl or "Special" }
      end
      return segs
    end,
    shortcuts = {},
    auto_refresh_ms = STATS_REFRESH_MS,
  }
end

local function make_explorer_subview(container_id, container_name, path)
  local self
  self = {
    title = "Files: " .. container_name .. ":" .. path,
    produce = function(cb)
      local r = cli.run_sync({ "exec", container_id, "ls", "-1Ap", path })
      if not r.ok then
        cb({})
        vim.notify(
          r.stderr ~= "" and r.stderr or "ls failed",
          vim.log.levels.ERROR,
          { title = "Docker" }
        )
        return
      end
      local items = {}
      if path ~= "/" then
        items[#items + 1] = {
          text = "../",
          name = "..",
          is_dir = true,
          path = parent_path(path),
          container_id = container_id,
          container_name = container_name,
        }
      end
      local dirs, files = {}, {}
      for line in (r.stdout or ""):gmatch("[^\r\n]+") do
        local is_dir = line:sub(-1) == "/"
        local name = is_dir and line:sub(1, -2) or line
        local entry = {
          text = line,
          name = name,
          is_dir = is_dir,
          path = join_path(path, name),
          container_id = container_id,
          container_name = container_name,
        }
        if is_dir then
          dirs[#dirs + 1] = entry
        else
          files[#files + 1] = entry
        end
      end
      vim.list_extend(items, dirs)
      vim.list_extend(items, files)
      cb(items)
    end,
    format = function(item)
      if item.is_dir then
        return { { item.name .. "/", "Directory" } }
      end
      return { { item.name, "Normal" } }
    end,
    shortcuts = {},
    on_select = function(item, ctx)
      if item.is_dir then
        ctx.open_subview(make_explorer_subview(container_id, container_name, item.path))
      else
        preview_file(item, ctx)
      end
    end,
  }
  return self
end

function M.build_inspect_sections(d)
  local sections = {}
  local cfg = d.Config or {}
  local hostcfg = d.HostConfig or {}
  local state = d.State or {}
  local netset = d.NetworkSettings or {}

  table.insert(sections, {
    name = "Identity",
    rows = {
      { "Name",    (d.Name or ""):gsub("^/", "") },
      { "Id",      (d.Id or ""):sub(1, 12) },
      { "Image",   cfg.Image or "" },
      { "Created", d.Created or "" },
      { "Driver",  d.Driver or "" },
      { "Platform", d.Platform or "" },
    },
  })

  table.insert(sections, {
    name = "State",
    rows = {
      { "Status",        state.Status or "" },
      { "PID",           tostring(state.Pid or "") },
      { "Started",       state.StartedAt or "" },
      { "Finished",      (state.FinishedAt and state.FinishedAt ~= "0001-01-01T00:00:00Z") and state.FinishedAt or "" },
      { "Exit code",     tostring(state.ExitCode or 0) },
      { "Restart count", tostring(d.RestartCount or 0) },
      { "OOM killed",    tostring(state.OOMKilled) },
    },
  })

  table.insert(sections, {
    name = "Config",
    rows = {
      { "Hostname",   cfg.Hostname or "" },
      { "User",       cfg.User or "" },
      { "Workdir",    cfg.WorkingDir or "" },
      { "Entrypoint", table.concat(cfg.Entrypoint or {}, " ") },
      { "Cmd",        table.concat(cfg.Cmd or {}, " ") },
      { "Tty",        tostring(cfg.Tty) },
      { "Network mode", hostcfg.NetworkMode or "" },
      { "Restart policy", (hostcfg.RestartPolicy or {}).Name or "" },
      { "Auto-remove",   tostring(hostcfg.AutoRemove) },
    },
  })

  local net_rows = {}
  for net_name, net in pairs(netset.Networks or {}) do
    local ip = net.IPAddress or ""
    local mac = net.MacAddress or ""
    local v = ip
    if mac ~= "" then v = v .. "  (mac " .. mac .. ")" end
    table.insert(net_rows, { net_name, v })
  end
  for port, bindings in pairs(netset.Ports or {}) do
    if bindings then
      for _, b in ipairs(bindings) do
        table.insert(net_rows, { port, ((b.HostIp ~= "" and b.HostIp) or "0.0.0.0") .. ":" .. (b.HostPort or "") })
      end
    else
      table.insert(net_rows, { port, "(exposed, no host bind)" })
    end
  end
  if #net_rows > 0 then
    table.insert(sections, { name = "Networking", rows = net_rows })
  end

  local mount_rows = {}
  for _, m in ipairs(d.Mounts or {}) do
    local typ = m.Type or "?"
    local src = m.Source or m.Name or ""
    local dst = m.Destination or ""
    local ro = m.RW == false and " (ro)" or ""
    table.insert(mount_rows, { dst, src .. "  [" .. typ .. "]" .. ro })
  end
  if #mount_rows > 0 then
    table.insert(sections, { name = "Mounts", rows = mount_rows })
  end

  local env_rows = {}
  for _, e in ipairs(cfg.Env or {}) do
    local k, v = e:match("^([^=]+)=(.*)$")
    if k then
      table.insert(env_rows, { k, v })
    end
  end
  if #env_rows > 0 then
    table.insert(sections, { name = "Environment", rows = env_rows })
  end

  local label_rows = {}
  for k, v in pairs(cfg.Labels or {}) do
    table.insert(label_rows, { k, v })
  end
  table.sort(label_rows, function(a, b) return a[1] < b[1] end)
  if #label_rows > 0 then
    table.insert(sections, { name = "Labels", rows = label_rows })
  end

  return sections
end

M.shortcuts = {
  {
    key = "s", desc = "Start/Stop",
    fn = function(item, ctx)
      local cmd = (item.state == "running") and "stop" or "start"
      cli.run_action({ cmd, item.id }, ctx.refresh)
    end,
  },
  { key = "r", desc = "Restart",
    fn = function(item, ctx) cli.run_action({ "restart", item.id }, ctx.refresh) end,
  },
  {
    key = "m", desc = "Stats",
    fn = function(item, ctx)
      if item.state ~= "running" then
        vim.notify("container not running", vim.log.levels.WARN, { title = "Docker" })
        return
      end
      ctx.open_subview(make_stats_subview(item.id, item.name))
    end,
  },
  {
    key = "f", desc = "Files",
    fn = function(item, ctx)
      if item.state ~= "running" then
        vim.notify("container not running", vim.log.levels.WARN, { title = "Docker" })
        return
      end
      local workdir = get_workdir(item.id)
      ctx.open_subview(make_explorer_subview(item.id, item.name, workdir))
    end,
  },
  { key = "o", desc = "Logs",    fn = action_logs },
  {
    key = "L", desc = "Logs (pane)",
    fn = function(item, ctx)
      local cfg = require("docker").config
      ctx.open_subview(ui.make_log_subview("logs: " .. item.name, function()
        local r = cli.run_sync({ "logs", "--tail", tostring(cfg.log_tail), item.id })
        return (r.stdout or "") .. (r.stderr or "")
      end))
    end,
  },
  { key = "e", desc = "Shell",   fn = action_shell },
  {
    key = "i", desc = "Inspect",
    fn = function(item, ctx)
      local result = cli.run_sync({ "inspect", item.id })
      if not result.ok then
        vim.notify(result.stderr, vim.log.levels.ERROR, { title = "Docker" })
        return
      end
      local ok, parsed = pcall(vim.json.decode, result.stdout)
      if not ok or type(parsed) ~= "table" or not parsed[1] then
        ctx.open_subview(ui.make_json_subview("inspect: " .. item.name, result.stdout))
        return
      end
      ctx.open_subview(ui.make_structured_subview(
        "inspect: " .. item.name,
        require("docker.containers").build_inspect_sections(parsed[1])
      ))
    end,
  },
  {
    key = "x", desc = "Remove",
    fn = function(item, ctx)
      ui.confirm_and_run("remove container " .. item.name, function()
        cli.run_action({ "rm", item.id }, ctx.refresh)
      end)
    end,
  },
  {
    key = "X", desc = "Force Rm",
    fn = function(item, ctx)
      ui.confirm_and_run("FORCE remove container " .. item.name, function()
        cli.run_action({ "rm", "-f", item.id }, ctx.refresh)
      end)
    end,
  },
}

M.produce = ui.produce_from_args({ "ps", "-a", "--format", "{{json .}}" }, make_item)

return M

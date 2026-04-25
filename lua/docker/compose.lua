local cli = require("docker.cli")
local ui = require("docker.ui")
local terminal = require("docker.terminal")

local M = {}

local COMPOSE_FILES = { "compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml" }

---Regex-parse minimal YAML: returns the top-level `name:` value (or nil) and a count
---of top-level `services:` children (two-space-indented keys).
---@param text string
---@return string|nil name, integer service_count, string[] service_names
function M.parse_compose_yaml(text)
  local name = nil
  for line in text:gmatch("[^\r\n]+") do
    local m = line:match("^name:%s*[\"']?([%w%-%._]+)[\"']?%s*$")
    if m then
      name = m
      break
    end
  end

  local services = {}
  local in_services = false
  for line in text:gmatch("[^\r\n]+") do
    if line:match("^services:%s*$") then
      in_services = true
    elseif in_services then
      if line:match("^[%w]") then
        in_services = false
      else
        local svc = line:match("^  ([%w%-%._]+):%s*$")
        if svc then
          services[#services + 1] = svc
        end
      end
    end
  end

  return name, #services, services
end

---@param dir string
---@return string|nil path
local function find_cwd_compose(dir)
  for _, candidate in ipairs(COMPOSE_FILES) do
    local p = dir .. "/" .. candidate
    if vim.fn.filereadable(p) == 1 then
      return p
    end
  end
  return nil
end

---`docker compose ls --format json` returns one JSON array, not NDJSON.
---@param cb fun(items: table[]|nil, err: string|nil)
---@return vim.SystemObj
local function list_running_projects(cb)
  return vim.system(
    { "docker", "compose", "ls", "--all", "--format", "json" },
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        if cli.is_daemon_down(result.stderr or "") then
          cb({}, "Docker daemon not running")
        else
          cb(nil, result.stderr)
        end
        return
      end
      local ok, arr = pcall(vim.json.decode, result.stdout or "")
      if not ok or type(arr) ~= "table" then
        cb({}, nil)
        return
      end
      cb(arr, nil)
    end)
  )
end

---@param cb fun(items: table[]|nil, err: string|nil)
---@return vim.SystemObj|nil
local function produce_projects(cb)
  return list_running_projects(function(arr, err)
    if err then
      cb(nil, err)
      return
    end

    local items = {}
    local by_name = {}
    for _, proj in ipairs(arr) do
      local item = {
        text = proj.Name or "",
        name = proj.Name or "",
        status = proj.Status or "",
        config_files = proj.ConfigFiles or "",
        service_count = 0,
        running = true,
      }
      items[#items + 1] = item
      by_name[item.name] = item
    end

    local cwd = vim.fn.getcwd()
    local path = find_cwd_compose(cwd)
    if path then
      local f = io.open(path, "r")
      if f then
        local text = f:read("*a")
        f:close()
        local cname, count = M.parse_compose_yaml(text)
        local project_name = cname or vim.fn.fnamemodify(cwd, ":t")
        if not by_name[project_name] then
          items[#items + 1] = {
            text = project_name,
            name = project_name,
            status = "down",
            config_files = path,
            service_count = count,
            running = false,
            cwd_file = path,
          }
        end
      end
    end

    table.sort(items, function(a, b)
      if a.running ~= b.running then
        return a.running
      end
      return a.name < b.name
    end)

    cb(items, nil)
  end)
end

---`docker compose -p <project> ps --format json` returns NDJSON.
---@param project_name string
---@param cb fun(items: table[]|nil, err: string|nil)
---@return vim.SystemObj
local function list_services(project_name, cb)
  return vim.system(
    { "docker", "compose", "-p", project_name, "ps", "--all", "--format", "json" },
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        cb(nil, result.stderr)
        return
      end
      local out = result.stdout or ""
      local items = {}
      for line in out:gmatch("[^\r\n]+") do
        local ok, obj = pcall(vim.json.decode, line)
        if ok and type(obj) == "table" then
          items[#items + 1] = obj
        end
      end
      cb(items, nil)
    end)
  )
end

---@param project table
---@param cb fun(items: table[]|nil, err: string|nil)
---@return vim.SystemObj|nil
local function produce_services(project, cb)
  return list_services(project.name, function(rows, err)
    if err then
      cb(nil, err)
      return
    end

    if rows and #rows > 0 then
      local items = {}
      for _, raw in ipairs(rows) do
        items[#items + 1] = {
          text = (raw.Service or raw.Name or "") .. " " .. (raw.State or ""),
          name = raw.Service or raw.Name or "",
          state = raw.State or "?",
          image = raw.Image or "",
          service = raw.Service or raw.Name or "",
          project = project.name,
          raw = raw,
        }
      end
      cb(items, nil)
      return
    end

    if project.cwd_file then
      local f = io.open(project.cwd_file, "r")
      if f then
        local text = f:read("*a")
        f:close()
        local _, _, names = M.parse_compose_yaml(text)
        local items = {}
        for _, n in ipairs(names) do
          items[#items + 1] = {
            text = n .. " down",
            name = n,
            state = "down",
            image = "",
            service = n,
            project = project.name,
          }
        end
        cb(items, nil)
        return
      end
    end

    cb({}, nil)
  end)
end

local function format_service(item)
  local state_hl = (item.state == "running") and "DiagnosticOk" or "Comment"
  return {
    { string.format("%-9s ", item.state:sub(1, 9)), state_hl },
    { string.format("%-24s ", item.name:sub(1, 24)), "SnacksPickerLabel" },
    { item.image, "SnacksPickerDir" },
  }
end

local SERVICE_SHORTCUTS = {
  {
    key = "o", desc = "Logs",
    fn = function(item)
      terminal.open_split({
        "docker", "compose", "-p", item.project, "logs", "-f", "--tail", "200", item.service,
      })
    end,
  },
  {
    key = "L", desc = "Logs (pane)",
    fn = function(item, ctx)
      local cfg = require("docker").config
      ctx.open_subview(ui.make_log_subview(
        "logs: " .. item.project .. "/" .. item.service,
        function()
          local r = cli.run_sync({
            "compose", "-p", item.project, "logs", "--tail", tostring(cfg.log_tail), item.service,
          })
          return (r.stdout or "") .. (r.stderr or "")
        end
      ))
    end,
  },
  {
    key = "s", desc = "Start/Stop",
    fn = function(item, ctx)
      local cmd = (item.state == "running") and "stop" or "start"
      cli.run_action({ "compose", "-p", item.project, cmd, item.service }, ctx.refresh)
    end,
  },
  {
    key = "r", desc = "Restart",
    fn = function(item, ctx)
      cli.run_action({ "compose", "-p", item.project, "restart", item.service }, ctx.refresh)
    end,
  },
  {
    key = "e", desc = "Shell",
    fn = function(item, ctx)
      if item.state ~= "running" then
        vim.notify("service not running", vim.log.levels.WARN, { title = "Docker" })
        return
      end
      local cfg = require("docker").config
      ctx.swap_list_with_terminal({
        "docker", "compose", "-p", item.project, "exec", item.service, cfg.shell,
      })
    end,
  },
}

function M.format(item)
  return {
    { string.format("%-9s ", item.status:sub(1, 9)), item.running and "DiagnosticOk" or "Comment" },
    { string.format("%-24s ", item.name:sub(1, 24)), "SnacksPickerLabel" },
    { string.format("%3d svc ", item.service_count), "Comment" },
    { item.config_files, "SnacksPickerDir" },
  }
end

M.shortcuts = {
  {
    key = "u", desc = "Up/Down",
    fn = function(item, ctx)
      if item.running then
        ui.confirm_and_run("compose down " .. item.name, function()
          cli.run_action({ "compose", "-p", item.name, "down" }, ctx.refresh)
        end)
      else
        vim.notify("compose up: " .. item.name, vim.log.levels.INFO, { title = "Docker" })
        cli.run_action({ "compose", "-f", item.cwd_file, "up", "-d" }, function()
          vim.notify("compose up complete: " .. item.name, vim.log.levels.INFO, { title = "Docker" })
          if ctx.refresh then ctx.refresh() end
        end)
      end
    end,
  },
  {
    key = "r", desc = "Restart",
    fn = function(item, ctx)
      if not item.running then
        vim.notify("project " .. item.name .. " is not running", vim.log.levels.WARN, { title = "Docker" })
        return
      end
      cli.run_action({ "compose", "-p", item.name, "restart" }, ctx.refresh)
    end,
  },
  {
    key = "o", desc = "Logs",
    fn = function(item)
      if not item.running then
        vim.notify("project " .. item.name .. " is not running", vim.log.levels.WARN, { title = "Docker" })
        return
      end
      terminal.open_split({ "docker", "compose", "-p", item.name, "logs", "-f", "--tail", "200" })
    end,
  },
  {
    key = "L", desc = "Logs (pane)",
    fn = function(item, ctx)
      if not item.running then
        vim.notify("project " .. item.name .. " is not running", vim.log.levels.WARN, { title = "Docker" })
        return
      end
      local cfg = require("docker").config
      ctx.open_subview(ui.make_log_subview("logs: " .. item.name, function()
        local r = cli.run_sync({ "compose", "-p", item.name, "logs", "--tail", tostring(cfg.log_tail) })
        return (r.stdout or "") .. (r.stderr or "")
      end))
    end,
  },
  {
    key = "s", desc = "Services",
    fn = function(item, ctx)
      ctx.open_subview({
        title = "Compose: " .. item.name,
        produce = function(cb) return produce_services(item, cb) end,
        format = format_service,
        shortcuts = SERVICE_SHORTCUTS,
      })
    end,
  },
}

M.produce = produce_projects

return M

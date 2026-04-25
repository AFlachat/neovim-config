local cli = require("docker.cli")
local ui = require("docker.ui")

local M = {}

---@param raw table
local function make_item(raw)
  return {
    text = (raw.Name or "") .. " " .. (raw.Driver or ""),
    name = raw.Name or "",
    id = raw.ID or "",
    driver = raw.Driver or "",
    scope = raw.Scope or "",
    raw = raw,
  }
end

function M.format(item)
  return {
    { string.format("%-28s ", item.name:sub(1, 28)), "SnacksPickerLabel" },
    { string.format("%-10s ", item.driver), "Comment" },
    { item.scope, "SnacksPickerDir" },
  }
end

local BUILTIN = { bridge = true, host = true, none = true }

function M.build_inspect_sections(d)
  local sections = {}
  local ipam = d.IPAM or {}

  table.insert(sections, {
    name = "Identity",
    rows = {
      { "Name",       d.Name or "" },
      { "Id",         (d.Id or ""):sub(1, 19) },
      { "Driver",     d.Driver or "" },
      { "Scope",      d.Scope or "" },
      { "Created",    d.Created or "" },
      { "Internal",   tostring(d.Internal) },
      { "Attachable", tostring(d.Attachable) },
      { "EnableIPv6", tostring(d.EnableIPv6) },
    },
  })

  local ipam_rows = { { "Driver", ipam.Driver or "" } }
  for i, c in ipairs(ipam.Config or {}) do
    table.insert(ipam_rows, {
      string.format("Config %d", i),
      (c.Subnet or "") .. "  gw " .. (c.Gateway or ""),
    })
  end
  table.insert(sections, { name = "IPAM", rows = ipam_rows })

  local container_rows = {}
  for cid, c in pairs(d.Containers or {}) do
    container_rows[#container_rows + 1] = {
      c.Name or cid:sub(1, 12),
      (c.IPv4Address or "") .. "  (mac " .. (c.MacAddress or "") .. ")",
    }
  end
  table.sort(container_rows, function(a, b) return a[1] < b[1] end)
  if #container_rows > 0 then
    table.insert(sections, { name = "Connected Containers (" .. #container_rows .. ")", rows = container_rows })
  end

  local opt_rows = {}
  for k, v in pairs(d.Options or {}) do
    table.insert(opt_rows, { k, tostring(v) })
  end
  table.sort(opt_rows, function(a, b) return a[1] < b[1] end)
  if #opt_rows > 0 then
    table.insert(sections, { name = "Options", rows = opt_rows })
  end

  local label_rows = {}
  for k, v in pairs(d.Labels or {}) do
    table.insert(label_rows, { k, tostring(v) })
  end
  table.sort(label_rows, function(a, b) return a[1] < b[1] end)
  if #label_rows > 0 then
    table.insert(sections, { name = "Labels", rows = label_rows })
  end

  return sections
end

M.shortcuts = {
  {
    key = "i", desc = "Inspect",
    fn = function(item, ctx)
      local result = cli.run_sync({ "network", "inspect", item.name })
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
        require("docker.networks").build_inspect_sections(parsed[1])
      ))
    end,
  },
  {
    key = "x", desc = "Remove",
    fn = function(item, ctx)
      if BUILTIN[item.name] then
        vim.notify("cannot remove builtin network " .. item.name, vim.log.levels.WARN, { title = "Docker" })
        return
      end
      ui.confirm_and_run("remove network " .. item.name, function()
        cli.run_action({ "network", "rm", item.name }, ctx.refresh)
      end)
    end,
  },
}

M.produce = ui.produce_from_args({ "network", "ls", "--format", "{{json .}}" }, make_item)

return M

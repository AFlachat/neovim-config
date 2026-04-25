local cli = require("docker.cli")
local ui = require("docker.ui")

local M = {}

---@param raw table
local function make_item(raw)
  return {
    text = (raw.Name or "") .. " " .. (raw.Driver or ""),
    name = raw.Name or "",
    driver = raw.Driver or "",
    raw = raw,
  }
end

function M.format(item)
  return {
    { string.format("%-40s ", item.name:sub(1, 40)), "SnacksPickerLabel" },
    { item.driver, "Comment" },
  }
end

function M.build_inspect_sections(d)
  local sections = {}

  table.insert(sections, {
    name = "Identity",
    rows = {
      { "Name",       d.Name or "" },
      { "Driver",     d.Driver or "" },
      { "Mountpoint", d.Mountpoint or "" },
      { "Scope",      d.Scope or "" },
      { "Created",    d.CreatedAt or "" },
    },
  })

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

  local stat_rows = {}
  for k, v in pairs(d.UsageData or {}) do
    table.insert(stat_rows, { k, tostring(v) })
  end
  if #stat_rows > 0 then
    table.insert(sections, { name = "Usage", rows = stat_rows })
  end

  return sections
end

M.shortcuts = {
  {
    key = "i", desc = "Inspect",
    fn = function(item, ctx)
      local result = cli.run_sync({ "volume", "inspect", item.name })
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
        require("docker.volumes").build_inspect_sections(parsed[1])
      ))
    end,
  },
  {
    key = "x", desc = "Remove",
    fn = function(item, ctx)
      ui.confirm_and_run("remove volume " .. item.name, function()
        cli.run_action({ "volume", "rm", item.name }, ctx.refresh)
      end)
    end,
  },
}

M.produce = ui.produce_from_args({ "volume", "ls", "--format", "{{json .}}" }, make_item)

return M

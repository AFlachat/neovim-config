local cli = require("docker.cli")
local ui = require("docker.ui")

local M = {}

---`docker images --format '{{json .}}'` fields: Repository, Tag, ID, Size, CreatedSince.
---@param raw table
local function make_item(raw)
  local repo = raw.Repository or "<none>"
  local tag = raw.Tag or "<none>"
  local full = repo .. ":" .. tag
  return {
    text = full .. " " .. (raw.ID or ""),
    name = full,
    repo = repo,
    tag = tag,
    id = raw.ID,
    short_id = (raw.ID or ""):sub(1, 12),
    size = raw.Size or "",
    created = raw.CreatedSince or "",
    raw = raw,
  }
end

function M.format(item)
  return {
    { string.format("%-40s ", item.name:sub(1, 40)), "SnacksPickerLabel" },
    { string.format("%-14s ", item.short_id), "Comment" },
    { string.format("%-10s ", item.size), "SnacksPickerDir" },
    { item.created, "Comment" },
  }
end

function M.build_inspect_sections(d)
  local sections = {}
  local cfg = d.Config or {}

  local function format_size(bytes)
    if not bytes then return "" end
    local kb = bytes / 1024
    if kb < 1024 then return string.format("%.1f KiB", kb) end
    local mb = kb / 1024
    if mb < 1024 then return string.format("%.1f MiB", mb) end
    return string.format("%.2f GiB", mb / 1024)
  end

  table.insert(sections, {
    name = "Identity",
    rows = {
      { "Id",       (d.Id or ""):sub(1, 19) },
      { "Tags",     table.concat(d.RepoTags or {}, "  ") },
      { "Digests",  table.concat(d.RepoDigests or {}, "  ") },
      { "Created",  d.Created or "" },
      { "Size",     format_size(d.Size) },
      { "Virtual",  format_size(d.VirtualSize) },
      { "Arch / OS", (d.Architecture or "") .. " / " .. (d.Os or "") },
    },
  })

  table.insert(sections, {
    name = "Config",
    rows = {
      { "Author",     d.Author or "" },
      { "Comment",    d.Comment or "" },
      { "User",       cfg.User or "" },
      { "Workdir",    cfg.WorkingDir or "" },
      { "Entrypoint", table.concat(cfg.Entrypoint or {}, " ") },
      { "Cmd",        table.concat(cfg.Cmd or {}, " ") },
    },
  })

  local exposed_rows = {}
  for port in pairs(cfg.ExposedPorts or {}) do
    table.insert(exposed_rows, { port, "exposed" })
  end
  if #exposed_rows > 0 then
    table.insert(sections, { name = "Exposed Ports", rows = exposed_rows })
  end

  local env_rows = {}
  for _, e in ipairs(cfg.Env or {}) do
    local k, v = e:match("^([^=]+)=(.*)$")
    if k then table.insert(env_rows, { k, v }) end
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

  local layer_rows = {}
  for i, l in ipairs((d.RootFS or {}).Layers or {}) do
    table.insert(layer_rows, { string.format("layer %d", i), l:sub(1, 19) })
  end
  if #layer_rows > 0 then
    table.insert(sections, { name = "Layers (" .. #layer_rows .. ")", rows = layer_rows })
  end

  return sections
end

M.shortcuts = {
  {
    key = "i", desc = "Inspect",
    fn = function(item, ctx)
      local result = cli.run_sync({ "image", "inspect", item.id })
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
        require("docker.images").build_inspect_sections(parsed[1])
      ))
    end,
  },
  {
    key = "u", desc = "Pull",
    fn = function(item)
      if item.repo == "<none>" or item.tag == "<none>" then
        vim.notify("untagged image — cannot pull", vim.log.levels.WARN, { title = "Docker" })
        return
      end
      vim.notify("Pulling " .. item.name .. "…", vim.log.levels.INFO, { title = "Docker" })
      cli.run_action({ "pull", item.name }, function()
        vim.notify("Pulled " .. item.name, vim.log.levels.INFO, { title = "Docker" })
      end)
    end,
  },
  {
    key = "n", desc = "Run…",
    fn = function(item)
      vim.ui.input({ prompt = "docker run args (image " .. item.name .. "): " }, function(input)
        if not input or input == "" then return end
        local argv = { "run", "-d" }
        for token in input:gmatch("%S+") do
          argv[#argv + 1] = token
        end
        argv[#argv + 1] = item.name
        cli.run_action(argv, function()
          vim.notify("Started " .. item.name, vim.log.levels.INFO, { title = "Docker" })
        end)
      end)
    end,
  },
  {
    key = "x", desc = "Remove",
    fn = function(item, ctx)
      ui.confirm_and_run("remove image " .. item.name, function()
        cli.run_action({ "rmi", item.id }, ctx.refresh)
      end)
    end,
  },
}

M.produce = ui.produce_from_args({ "images", "--format", "{{json .}}" }, make_item)

return M

local cli = require("docker.cli")

local M = {}

---Helper: wrap `cli.run_json(args, ...)` into a produce(cb) function with
---daemon-down normalization.
---@param args string[]
---@param make_item fun(raw: table): table
---@return fun(cb: fun(items: table[]|nil, err: string|nil)): vim.SystemObj|nil
function M.produce_from_args(args, make_item)
  return function(cb)
    return cli.run_json(args, function(rows, err)
      if err then
        if cli.is_daemon_down(err) then
          cb({}, "Docker daemon not running")
        else
          cb(nil, err)
        end
        return
      end
      local items = {}
      for _, raw in ipairs(rows or {}) do
        items[#items + 1] = make_item(raw)
      end
      cb(items, nil)
    end)
  end
end

---Convert a list of `{ key, desc, fn }` shortcut tables into the Snacks
---border-footer format (list of `{ text, hl_group }` tuples). Appends any
---extra `{key,desc}` pairs at the end.
---@param shortcuts { key: string, desc: string }[]
---@param globals? { [1]: string, [2]: string }[]
---@return table footer
function M.shortcuts_to_footer(shortcuts, globals)
  local footer = {}
  local function push(key, desc)
    table.insert(footer, { " ", "SnacksFooter" })
    table.insert(footer, { " " .. key .. " ", "SnacksFooterKey" })
    table.insert(footer, { " " .. desc .. " ", "SnacksFooterDesc" })
  end
  for _, sc in ipairs(shortcuts) do
    push(sc.key, sc.desc)
  end
  if globals then
    for _, g in ipairs(globals) do
      push(g[1], g[2])
    end
  end
  table.insert(footer, { " ", "SnacksFooter" })
  return footer
end

---Tokenize a single line of pretty-printed JSON into Snacks `{text, hl}` segments.
---@param line string
---@return table[] segments
local function format_json_line(line)
  -- Empty / whitespace-only line.
  if line:match("^%s*$") then
    return { { line, nil } }
  end

  -- "key": <rest>
  local indent, key, sep, rest = line:match('^(%s*)"([^"]*)"(%s*:%s*)(.*)$')
  if indent then
    local segs = {
      { indent,                nil           },
      { '"' .. key .. '"',     "Identifier"  },
      { sep,                   "Operator"    },
    }
    if rest == "" then
      -- nothing
    elseif rest:sub(1, 1) == '"' then
      segs[#segs + 1] = { rest, "String" }
    elseif rest:match("^%-?%d") then
      segs[#segs + 1] = { rest, "Number" }
    elseif rest:match("^true") or rest:match("^false") then
      segs[#segs + 1] = { rest, "Boolean" }
    elseif rest:match("^null") then
      segs[#segs + 1] = { rest, "Constant" }
    elseif rest:sub(1, 1) == "{" or rest:sub(1, 1) == "[" then
      segs[#segs + 1] = { rest, "Delimiter" }
    else
      segs[#segs + 1] = { rest, nil }
    end
    return segs
  end

  -- Bracket-only line: }, ], [, {, with optional trailing comma.
  if line:match("^%s*[%[%]{}]+%s*,?%s*$") then
    return { { line, "Delimiter" } }
  end

  -- Quoted string in an array.
  local idt, str_with_tail = line:match('^(%s*)("[^"]*"%s*,?%s*)$')
  if idt then
    return { { idt, nil }, { str_with_tail, "String" } }
  end

  -- Bare scalar in an array.
  local idt2, scalar = line:match("^(%s*)([%w%-%.]+%s*,?%s*)$")
  if idt2 then
    if scalar:match("^%-?%d") then
      return { { idt2, nil }, { scalar, "Number" } }
    elseif scalar:match("^true") or scalar:match("^false") then
      return { { idt2, nil }, { scalar, "Boolean" } }
    elseif scalar:match("^null") then
      return { { idt2, nil }, { scalar, "Constant" } }
    end
  end

  return { { line, nil } }
end

---Build a structured subview from a list of `sections`.
---Each section: `{ name = "Title", rows = { {key, value, hl?}, ... } }`.
---Renders headers, indented key/value rows, separators between sections.
---@param title string
---@param sections { name: string, rows: { [1]: string, [2]: string, hl?: string }[] }[]
---@return table subview
function M.make_structured_subview(title, sections)
  local items = {}
  local function add(it)
    it.idx = #items + 1
    items[#items + 1] = it
  end
  for s_i, sect in ipairs(sections) do
    if s_i > 1 then
      add({ text = "", _kind = "blank" })
    end
    add({ text = sect.name, _kind = "header", _name = sect.name })
    for _, row in ipairs(sect.rows) do
      add({
        text = (row[1] or "") .. " " .. (row[2] or ""),
        _kind = "row",
        _key = row[1] or "",
        _value = row[2] or "",
        _hl = row.hl,
      })
    end
  end
  if #items == 0 then
    items = { { text = "(empty)", _kind = "row", _key = "", _value = "(empty)", idx = 1 } }
  end

  return {
    title = title,
    produce = function(cb) cb(items) end,
    format = function(it)
      if it._kind == "header" then
        return {
          { "─ ",            "Comment" },
          { it._name,        "Title"   },
          { " ",             "Comment" },
          { string.rep("─", 80), "Comment" },
        }
      elseif it._kind == "blank" then
        return { { "", nil } }
      else
        return {
          { "  ",                                 nil           },
          { string.format("%-18s ", it._key),     "Identifier"  },
          { it._value,                            it._hl or nil },
        }
      end
    end,
    shortcuts = {},
  }
end

---@param title string
---@param json_text string
---@return table subview
function M.make_json_subview(title, json_text)
  -- Use jq for pretty-printing if available, otherwise the docker inspect output is already pretty.
  local lines = vim.split(json_text, "\n", { plain = true })
  local items = {}
  for i, line in ipairs(lines) do
    items[#items + 1] = { text = line, _line = line, idx = i }
  end
  if #items == 0 then
    items = { { text = "(empty)", _line = "(empty)", idx = 1 } }
  end
  return {
    title = title,
    produce = function(cb) cb(items) end,
    format = function(it) return format_json_line(it._line) end,
    shortcuts = {},
  }
end

---Build a subview whose `produce` re-runs `fetch_text()` on every call.
---Suitable for live-tailing logs: combine with `auto_refresh_ms` and
---`scroll_to_bottom` so the picker re-fetches and follows latest output.
---@param title string
---@param fetch_text fun(): string
---@param opts? { interval_ms?: integer }
---@return table subview
function M.make_log_subview(title, fetch_text, opts)
  opts = opts or {}
  local function build_items()
    local text = fetch_text() or ""
    local lines = vim.split(text, "\n", { plain = true })
    local items = {}
    for i, line in ipairs(lines) do
      items[#items + 1] = { text = line, _line = line, idx = i }
    end
    if #items == 0 then
      items = { { text = "(no logs)", _line = "(no logs)", idx = 1 } }
    end
    return items
  end
  return {
    title = title,
    produce = function(cb) cb(build_items()) end,
    format = function(it) return { { it._line, nil } } end,
    shortcuts = {},
    auto_refresh_ms = opts.interval_ms or 2000,
    scroll_to_bottom = true,
  }
end

local SPARK_BLOCKS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

---Render a list of numeric values as a Unicode-block sparkline.
---@param values number[]
---@param scale_max? number  -- normalize to this max (default: max of values)
---@return string
function M.sparkline(values, scale_max)
  if #values == 0 then return "" end
  local max = scale_max
  if not max or max <= 0 then
    max = 0
    for _, v in ipairs(values) do
      if v > max then max = v end
    end
  end
  if max <= 0 then
    return string.rep(SPARK_BLOCKS[1], #values)
  end
  local out = {}
  for _, v in ipairs(values) do
    local idx = math.max(1, math.min(#SPARK_BLOCKS, math.ceil((v / max) * #SPARK_BLOCKS)))
    out[#out + 1] = SPARK_BLOCKS[idx]
  end
  return table.concat(out)
end

---@param name string
---@param fn fun()
function M.confirm_and_run(name, fn)
  local cfg = require("docker").config
  if not cfg.confirm_destructive then
    fn()
    return
  end
  local choice = vim.fn.confirm("Docker: " .. name .. "?", "&Yes\n&No", 2)
  if choice == 1 then
    fn()
  end
end

return M

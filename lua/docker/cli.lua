local M = {}

---Split output on newlines and vim.json.decode each non-empty line.
---Malformed lines are skipped.
---@param stdout string
---@return table[] items
function M.parse_ndjson(stdout)
  local items = {}
  if not stdout or stdout == "" then
    return items
  end
  for line in stdout:gmatch("[^\r\n]+") do
    if line ~= "" then
      local ok, obj = pcall(vim.json.decode, line)
      if ok and type(obj) == "table" then
        items[#items + 1] = obj
      end
    end
  end
  return items
end

---@param stderr string
---@return boolean
function M.is_daemon_down(stderr)
  if not stderr then
    return false
  end
  return stderr:find("Cannot connect to the Docker daemon", 1, true) ~= nil
    or stderr:find("is the docker daemon running", 1, true) ~= nil
end

---Run `docker <args...>` synchronously. Use only for quick one-shots.
---@param args string[]
---@return { ok: boolean, stdout: string, stderr: string, code: integer }
function M.run_sync(args)
  local cmd = vim.list_extend({ "docker" }, args)
  local result = vim.system(cmd, { text = true }):wait()
  return {
    ok = result.code == 0,
    stdout = result.stdout or "",
    stderr = result.stderr or "",
    code = result.code,
  }
end

---Run `docker <args...>` asynchronously and parse stdout as NDJSON.
---@param args string[]
---@param cb fun(items: table[]|nil, err: string|nil)
---@return vim.SystemObj handle
function M.run_json(args, cb)
  local cmd = vim.list_extend({ "docker" }, args)
  return vim.system(
    cmd,
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        cb(nil, result.stderr or ("docker exited " .. result.code))
        return
      end
      cb(M.parse_ndjson(result.stdout or ""), nil)
    end)
  )
end

---Run a mutating `docker <args...>` command; notify on failure, call on_done on success.
---@param args string[]
---@param on_done? fun()
function M.run_action(args, on_done)
  local cmd = vim.list_extend({ "docker" }, args)
  vim.system(
    cmd,
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        local msg = (result.stderr ~= "" and result.stderr) or ("docker exited " .. result.code)
        vim.notify(msg, vim.log.levels.ERROR, { title = "Docker" })
        return
      end
      if on_done then
        on_done()
      end
    end)
  )
end

return M

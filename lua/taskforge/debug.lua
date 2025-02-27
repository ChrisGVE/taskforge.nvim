-- Copyright (c) 2025 Christian C. Berclaz
--
-- MIT License

-- Credit for the inspiration of this module goes to folke's Snacks.debug module

---@class debug
---@overload fun(...)
local M = setmetatable({}, {
  __call = function(t, ...)
    return t.inspect(...)
  end,
})

M.debug_config = {}

local debug_query = "Sn"
local cache_dir = {}

M.meta = {
  desc = "Pretty inspect & backtraces for debugging",
}

local uv = vim.uv or vim.loop

vim.schedule(function()
  Snacks.util.set_hl({
    Indent = "LineNr",
    Print = "NonText",
  }, { prefix = "SnacksDebug", default = true })
end)

-- Show a notification with a pretty printed dump of the object(s)
-- with lua treesitter highlighting and the location of the caller
function M.inspect(...)
  local len = select("#", ...) ---@type number
  local obj = { ... } ---@type unknown[]
  local caller = debug.getinfo(1, "S")
  for level = 2, 10 do
    local info = debug.getinfo(level, "S")
    if
      info
      and info.source ~= caller.source
      and info.what ~= "C"
      and info.source ~= "lua"
      and info.source ~= "@" .. (os.getenv("MYVIMRC") or "")
    then
      caller = info
      break
    end
  end
  vim.schedule(function()
    local title = "Debug: " .. vim.fn.fnamemodify(caller.source:sub(2), ":~:.") .. ":" .. caller.linedefined
    Snacks.notify.warn(vim.inspect(len == 1 and obj[1] or len > 0 and obj or nil), { title = title, ft = "lua" })
  end)
end

-- Show a notification with a pretty backtrace
---@param msg? string|string[]
---@param opts? snacks.notify.Opts
function M.backtrace(msg, opts)
  opts = vim.tbl_deep_extend("force", {
    level = vim.log.levels.WARN,
    title = "Backtrace",
  }, opts or {})
  ---@type string[]
  local trace = type(msg) == "table" and msg or type(msg) == "string" and { msg } or {}
  for level = 2, 20 do
    local info = debug.getinfo(level, "Sln")
    if info and info.what ~= "C" and info.source ~= "lua" and not info.source:find("snacks[/\\]debug") then
      local line = "- `" .. vim.fn.fnamemodify(info.source:sub(2), ":p:~:.") .. "`:" .. info.currentline
      if info.name then
        line = line .. " _in_ **" .. info.name .. "**"
      end
      table.insert(trace, line)
    end
  end
  local result = #trace > 0 and (table.concat(trace, "\n")) or ""
  Snacks.notify(result, opts)
end

-- Very simple function to profile a lua function.
-- * **flush**: set to `true` to use `jit.flush` in every iteration.
-- * **count**: defaults to 100
-- * **show**: default to true
---@param fn fun()
---@param opts? {count?: number, flush?: boolean, title?: string}
function M.profile(fn, opts)
  opts = vim.tbl_extend("force", { count = 100, flush = true, show = true }, opts or {})
  local start = uv.hrtime()
  for _ = 1, opts.count, 1 do
    if opts.flush then
      jit.flush(fn, true)
    end
    fn()
  end
  Snacks.notify(((uv.hrtime() - start) / 1e6 / opts.count) .. "ms", { title = opts.title or "Profile" })
end

---@param level integer
---@param debug_info table
---@return string|nil function_name, string|nil function_source
local function caller(level, debug_info)
  local function get_src(path_name)
    local source

    -- use cached value if available
    if cache_dir[path_name] ~= nil then
      return cache_dir[path_name]
    end

    -- when debugging a plugin, we'll have a structure of the kind /lua/<plugin>/file... so we look for this pattern first
    source = path_name:match(".*/lua/[^/]+/(.*).lua$"):gsub("/", ".")
    if source == nil then -- we are not in the normal pattern so we'll just return the parent folder and the filename
      source = path_name:match(".*/([^/]+/.*).lua$"):gsub("/", ".")
    end

    -- cache the new value before returning it
    cache_dir[path_name] = source

    return source
  end

  level = level + 1 -- this is to account for the fact by calling this function we are one level deeper
  if debug_info.name == nil or debug_info.name == "" then
    local name, source = caller(level, debug.getinfo(level, debug_query))
    return name .. ".fn", source -- we add the indication that there is an anonymous function
  else
    return debug_info.name, get_src(debug_info.source)
  end
end

-- Log a message to the file `./debug.log`.
-- - a timestamp will be added to every message.
-- - accepts multiple arguments and pretty prints them.
-- - if the argument is not a string, it will be printed using `vim.inspect`.
-- - if the message is smaller than 120 characters, it will be printed on a single line.
--
-- ```lua
-- Snacks.debug.log("Hello", { foo = "bar" }, 42)
-- -- 2024-11-08 08:56:52 Hello { foo = "bar" } 42
-- ```
function M.log(...)
  local level = 3 -- level 3 because we expect the caller to be a global function
  local caller_fn, caller_src = caller(level, debug.getinfo(level, debug_query))
  local file = M.debug_config.log_file or "./debug.log"
  local fd = io.open(file, "a+")
  if not fd then
    error(("Could no t open file %s for writing"):format(file))
  end
  local c = select("#", ...)
  local parts = {} ---@type string[]
  for i = 1, c do
    local v = select(i, ...)
    parts[i] = type(v) == "string" and v or vim.inspect(v)
  end
  local msg = " | " .. caller_src .. "." .. caller_fn
  local arg = table.concat(parts, " ")
  if #arg ~= 0 then
    msg = msg .. " | " .. arg
  end
  msg = #msg < (M.debug_config.log_max_len or 120) and msg:gsub("%s+", " ") or msg
  fd:write(os.date("%Y-%m-%d %H:%M:%S ") .. msg)
  fd:write("\n")
  fd:close()
end

---@alias debug.Trace {name: string, time: number, [number]:snacks.debug.Trace}
---@alias debug.Stat {name:string, time:number, count?:number, depth?:number}

---@type debug.Trace[]
M._traces = { { name = "__TOP__", time = 0 } }

---@param name string?
function M.trace(name)
  if name then
    local entry = { name = name, time = uv.hrtime() } ---@type snacks.debug.Trace
    table.insert(M._traces[#M._traces], entry)
    table.insert(M._traces, entry)
    return entry
  else
    local entry = assert(table.remove(M._traces), "trace not ended?") ---@type snacks.debug.Trace
    entry.time = uv.hrtime() - entry.time
    return entry
  end
end

---@param modname string
---@param mod? table
---@param suffix? string
function M.tracemod(modname, mod, suffix)
  mod = mod or require(modname)
  suffix = suffix or "."
  for k, v in pairs(mod) do
    if type(v) == "function" and k ~= "trace" then
      mod[k] = function(...)
        M.trace(modname .. suffix .. k)
        local ok, ret = pcall(v, ...)
        M.trace()
        return ok == false and error(ret) or ret
      end
    end
  end
end

---@param opts? {min?: number, show?:boolean}
---@return {summary:table<string, snacks.debug.Stat>, trace:snacks.debug.Stat[], traces:snacks.debug.Trace[]}
function M.stats(opts)
  opts = opts or {}
  local stack, lines, trace = {}, {}, {} ---@type string[], string[], snacks.debug.Stat[]
  local summary = {} ---@type table<string, snacks.debug.Stat>
  ---@param stat snacks.debug.Trace
  local function collect(stat)
    if #stack > 0 then
      local recursive = vim.list_contains(stack, stat.name)
      summary[stat.name] = summary[stat.name] or { time = 0, count = 0, name = stat.name }
      summary[stat.name].time = summary[stat.name].time + (recursive and 0 or stat.time)
      summary[stat.name].count = summary[stat.name].count + 1
      table.insert(trace, { name = stat.name, time = stat.time or 0, depth = #stack - 1 })
    end
    table.insert(stack, stat.name)
    for _, entry in ipairs(stat) do
      collect(entry)
    end
    table.remove(stack)
  end
  collect(M._traces[1])

  ---@param entries snacks.debug.Stat[]
  local function add(entries)
    for _, stat in ipairs(entries) do
      local ms = math.floor(stat.time / 1e4) / 1e2
      if ms >= (opts.min or 0) then
        local line = ("%s- `%s`: **%.2f**ms"):format(("  "):rep(stat.depth or 0), stat.name, ms)
        table.insert(lines, line .. (stat.count and (" ([%d])"):format(stat.count) or ""))
      end
    end
  end

  if opts.show ~= false then
    lines[#lines + 1] = "# Summary"
    summary = vim.tbl_values(summary)
    table.sort(summary, function(a, b)
      return a.time > b.time
    end)
    add(summary)
    lines[#lines + 1] = "\n# Trace"
    add(trace)
    Snacks.notify.warn(lines, { title = "Traces" })
  end
  return { summary = summary, trace = trace, tree = M._traces }
end

function M.size(bytes)
  local sizes = { "B", "KB", "MB", "GB", "TB" }
  local s = 1
  while bytes > 1024 and s < #sizes do
    bytes = bytes / 1024
    s = s + 1
  end
  return ("%.2f%s"):format(bytes, sizes[s])
end

---@param show? boolean
function M.metrics(show)
  collectgarbage("collect")
  local lines = {} ---@type string[]
  local function add(name, value)
    lines[#lines + 1] = ("- **%s**: %s"):format(name, value)
  end

  add("lua", M.size(collectgarbage("count") * 1024))

  for _, stat in ipairs({ "get_total_memory", "get_free_memory", "get_available_memory", "resident_set_memory" }) do
    add(stat:gsub("get_", ""):gsub("_", " "), M.size(uv[stat]()))
  end
  lines[#lines + 1] = ("```lua\n%s\n```"):format(vim.inspect(uv.getrusage()))
  if show == nil or show then
    Snacks.notify.warn(lines, { title = "Metrics" })
  else
    return "Metrics: " .. lines
  end
end

function M.setup(debug_config)
  if debug_config == nil then
    M.debug_config["debug"] = false
  else
    M.debug_config = debug_config
    if M.debug_config.debug == nil then
      M.debug_config.debug = false
    end
  end
  if M.debug_config.debug then
    vim.print = M.inspect
  end
  return M.debug_config.debug
end

return M

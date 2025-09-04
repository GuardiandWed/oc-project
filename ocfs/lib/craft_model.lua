-- /home/craft_model.lua
local component = require("component")

local M = {}
M.ME = component.isAvailable("me_controller") and component.me_controller or nil

-- КЕШИ (заполняются craft_boot/run на старте)
M.cache = {
  allMods = {},
  modsSet = {},
  ts = 0
}
M.craftCache = {
  rows = {},        -- { {entry, label, name, damage, mod}, ... }
  byMod = {},       -- mod -> array of rows
  built = false
}

-- Публичные сеттеры для предзагрузки
function M.set_all_mods(arr)
  M.cache.allMods, M.cache.modsSet = {}, {}
  for _,m in ipairs(arr or {}) do
    if m and not M.cache.modsSet[m] then
      M.cache.modsSet[m] = true
      M.cache.allMods[#M.cache.allMods+1] = m
    end
  end
  table.sort(M.cache.allMods)
  M.cache.ts = os.time()
end

function M.set_craft_cache(cache)
  cache = cache or {}
  M.craftCache.rows  = cache.rows or {}
  M.craftCache.byMod = cache.byMod or {}
  M.craftCache.built = cache.built and true or ( (#M.craftCache.rows>0) )
end

function M.get_all_mods()
  return M.cache.allMods or {}
end

-- Фоллбек — если захотим пересобрать (не используется при нормальном старте)
local function _raw_craftables(filter)
  if not M.ME then return {} end
  local ok, list = pcall(function() return M.ME.getCraftables(filter) end)
  if not ok or type(list) ~= "table" then return {} end
  return list
end

local function _stackOf(entry)
  local ok, st = pcall(entry.getItemStack, entry)
  if not ok or type(st) ~= "table" then return nil end
  return st
end

local function _modFromName(name)
  if not name then return "unknown" end
  local i = name:find(":")
  if not i or i <= 1 then return "unknown" end
  return name:sub(1, i-1)
end

local function _match(hay, needle, exact)
  if not needle or needle == "" then return true end
  hay    = tostring(hay or "")
  needle = tostring(needle)
  if exact then
    return hay:lower() == needle:lower()
  else
    return hay:lower():find(needle:lower(), 1, true) ~= nil
  end
end

local function _getItemRecord(name, damage)
  if not M.ME then return nil end
  local ok, items = pcall(function() return M.ME.getItemsInNetwork({ name = name, damage = damage }) end)
  if ok and type(items)=="table" and items[1] then
    return items[1]
  end
  return nil
end

-- Основной источник теперь — кеш
function M.get_craftables(query, opts)
  opts = opts or {}
  local result = {}
  if not M.ME then return result end

  if M.craftCache and M.craftCache.built then
    local src
    if opts.modSet and next(opts.modSet) ~= nil then
      src = {}
      for mod,_ in pairs(opts.modSet) do
        local bucket = M.craftCache.byMod[mod]
        if bucket then
          for i=1,#bucket do src[#src+1] = bucket[i] end
        end
      end
    else
      src = M.craftCache.rows
    end

    local q = query
    for i = 1, #src do
      local row = src[i]
      if _match(row.label, q, false) then
        result[#result+1] = row
      end
    end
    return result
  end

  -- fallback (если кеша вдруг нет)
  local filter = (query and query ~= "") and { label = query } or nil
  local raw = _raw_craftables(filter)
  local modSet = opts.modSet
  for i = 1, #raw do
    local entry = raw[i]
    local st = _stackOf(entry) or {}
    local label = st.label or st.name or "<?>"
    local name  = st.name
    local dmg   = st.damage
    local mod   = _modFromName(name)
    if _match(label, query, false) and ((not modSet) or modSet[mod]) then
      result[#result+1] = { entry=entry, label=label, name=name, damage=dmg, mod=mod }
    end
  end
  return result
end

local function _resolve_entry(name, damage)
  if not M.ME or not name then return nil end
  -- 1) прямой фильтр
  local ok1, list = pcall(function() return M.ME.getCraftables({ name=name, damage=damage }) end)
  if ok1 and type(list)=="table" and list[1] then return list[1] end
  -- 2) полный перебор (редкий кейс, но помогает при несовпадении damage/NBT)
  local ok2, all = pcall(function() return M.ME.getCraftables() end)
  if ok2 and type(all)=="table" then
    for i=1,#all do
      local e = all[i]
      local okS, st = pcall(e.getItemStack, e)
      if okS and st and st.name==name and (damage==nil or st.damage==damage) then
        return e
      end
    end
  end
  return nil
end

function M.request_craft(craft_row, qty)
  qty = tonumber(qty) or 1
  if qty < 1 then qty = 1 end
  if not craft_row then return false, "no craft row" end

  local entry = craft_row.entry
  if not (entry and entry.request) then
    entry = _resolve_entry(craft_row.name, craft_row.damage)
  end
  if not (entry and entry.request) then
    return false, "craft entry not found"
  end
  local ok, res = pcall(function() return entry.request(qty) end)
  if not ok then return false, tostring(res) end
  return true, res
end



function M.get_cpu_summary()
  if not M.ME then return { total=0, busy=0, list={} } end
  local list = {}
  local ok, cpus = pcall(function()
    if M.ME.getCpus then return M.ME.getCpus() end
    if M.ME.getCraftingCPUs then return M.ME.getCraftingCPUs() end
    return {}
  end)
  if not ok or type(cpus) ~= "table" then cpus = {} end

  local busy = 0
  for i=1,#cpus do
    local c = cpus[i] or {}
    local entry = {
      name         = c.name or ("CPU "..i),
      storage      = c.storage or 0,
      coprocessors = c.coprocessors or c.coprocessorCount or 0,
      busy         = not not (c.busy or c.isBusy),
    }
    if entry.busy then busy = busy + 1 end
    list[#list+1] = entry
  end
  return { total=#list, busy=busy, list=list }
end

function M.get_item_info(craft_row)
  if not M.ME then return { ok=false, err="no ME" } end
  local label = craft_row and craft_row.label
  local name  = craft_row and craft_row.name
  local dmg   = craft_row and craft_row.damage

  local inNetCount, craftable = 0, false
  local rec = _getItemRecord(name, dmg)
  if rec then
    inNetCount = rec.size or 0
    craftable  = not not (rec.isCraftable or rec.is_craftable)
  end

  return {
    ok=true,
    label=label, name=name, damage=dmg,
    inNetwork=inNetCount,
    craftable=craftable,
  }
end

local function _arr(t)
  if type(t) ~= "table" then return {} end
  local out, n = {}, 0
  for i,v in ipairs(t) do out[#out+1]=v; n=n+1 end
  if n==0 then for _,v in pairs(t) do out[#out+1]=v end end
  return out
end

function M.get_jobs()
  if not M.ME then return {} end
  local ok, jobs = pcall(function()
    if M.ME.getCraftingJobs then return M.ME.getCraftingJobs() end
    return {}
  end)
  if not ok then return {} end
  jobs = _arr(jobs)
  local norm = {}
  for i, j in ipairs(jobs) do
    local id    = j.id or j.ID or j.JobID or i
    local label = j.label or j.name or (type(j)=="table" and j[1]) or ("Job "..i)
    norm[#norm+1] = { id = id, label = tostring(label) }
  end
  return norm
end

function M.cancel_job(id)
  if not M.ME then return false, "no ME" end
  local ok, res = pcall(function()
    if M.ME.cancelJob then return M.ME.cancelJob(id) end
    return false, "cancel not supported"
  end)
  if not ok then return false, res end
  if res == true then return true end
  return false, res
end


local fs  = require("filesystem")
local ser = require("serialization")

function M.save_cache(path)
  path = path or "/home/data/craft_cache.lua"
  local dir = path:match("^(.*)/[^/]+$")
  if dir and not fs.exists(dir) then fs.makeDirectory(dir) end
  local slim = {}
  for i=1,#(M.craftCache.rows or {}) do
    local r = M.craftCache.rows[i]
    slim[#slim+1] = { name=r.name, damage=r.damage, label=r.label, mod=r.mod }
  end
  local f = io.open(path, "w")
  if not f then return false, "cannot open file" end
  f:write(ser.serialize({ rows=slim }))
  f:close()
  return true
end

function M.load_cache(path)
  path = path or "/home/data/craft_cache.lua"
  if not fs.exists(path) then return false, "no file" end
  local f = io.open(path, "r"); if not f then return false, "cannot open" end
  local s = f:read("*a"); f:close()
  local ok, t = pcall(ser.unserialize, s)
  if not ok or type(t)~="table" then return false, "bad format" end
  M.craftCache.rows, M.craftCache.byMod = {}, {}
  for _,r in ipairs(t.rows or {}) do
    local mod = r.mod or "unknown"
    local row = { entry=nil, label=r.label, name=r.name, damage=r.damage, mod=mod }
    -- ленивое восстановление entry при запуске крафта (_resolve_entry)
    M.craftCache.rows[#M.craftCache.rows+1] = row
    local b = M.craftCache.byMod[mod]; if not b then b={} ; M.craftCache.byMod[mod]=b end
    b[#b+1] = row
  end
  M.craftCache.built = true
  return true
end


return M

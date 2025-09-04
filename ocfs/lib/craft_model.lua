-- /home/craft_model.lua
local component = require("component")

local M = {}
M.ME = component.isAvailable("me_controller") and component.me_controller or nil


-- ДО _raw_craftables вставь структуру кеша крафтов:
M.cache = M.cache or {
  allMods = {}, modsSet = {}, ts = 0
}
M.craftCache = {
  rows = {},        -- { {entry, label, name, damage, mod}, ... }
  byMod = {},       -- mod -> array of rows (ссылки на rows)
  built = false
}

-- NEW: полная предзагрузка списка крафтов со стеком и модами
function M.build_craft_cache(onProgress)
  M.craftCache = { rows = {}, byMod = {}, built = false }
  if not M.ME then return end

  local ok, raw = pcall(function() return M.ME.getCraftables() end)
  if not ok or type(raw) ~= "table" then return end

  local total = #raw
  for i = 1, total do
    local entry = raw[i]
    local st = _stackOf(entry) or {}
    local name  = st.name
    local row = {
      entry  = entry,
      label  = st.label or name or "<?>",
      name   = name,
      damage = st.damage,
      mod    = _modFromName(name),
    }
    M.craftCache.rows[#M.craftCache.rows+1] = row
    local m = row.mod or "unknown"
    local bucket = M.craftCache.byMod[m]
    if not bucket then bucket = {}; M.craftCache.byMod[m] = bucket end
    bucket[#bucket+1] = row

    if onProgress and (i % 25 == 0 or i == total) then
      onProgress(i, total, row.label)
    end
  end
  M.craftCache.built = true
end


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

-- построй список модов один раз из всей сети
function M.rebuild_cache()
  M.cache = { allMods = {}, modsSet = {}, ts = os.time() }
  if not M.ME then return end
  local ok, items = pcall(function() return M.ME.getItemsInNetwork() end)
  if not ok or type(items) ~= "table" then return end
  local set = {}
  for i=1,#items do
    local it = items[i] or {}
    local name = it.name or (it.item and it.item.name)  -- иногда структура разная
    local mod = _modFromName(name)
    if mod ~= "unknown" then set[mod] = true end
  end
  local arr = {}
  for m,_ in pairs(set) do arr[#arr+1] = m end
  table.sort(arr)
  M.cache.allMods = arr
  M.cache.modsSet = set
end

function M.get_all_mods()
  return M.cache.allMods or {}
end

function M.get_craftables(query, opts)
  opts = opts or {}
  local result = {}
  if not M.ME then return result end

  -- если кеш готов — фильтруем по нему
  if M.craftCache and M.craftCache.built then
    local src
    if opts.modSet and next(opts.modSet) ~= nil then
      -- собрать объединённый список по выбранным модам (из byMod)
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

  -- fallback: без кеша (не должен срабатывать после старта)
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


function M.request_craft(craft_row, qty)
  if not craft_row or not craft_row.entry then
    return false, "bad craftable"
  end
  qty = tonumber(qty) or 1
  if qty < 1 then qty = 1 end
  local ok, res = pcall(function() return craft_row.entry.request(qty) end)
  if not ok then return false, res end
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

return M

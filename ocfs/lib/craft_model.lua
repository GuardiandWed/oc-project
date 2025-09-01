-- craft_model.lua
local component = require("component")

local M = {}
M.ME = component.isAvailable("me_controller") and component.me_controller or nil

local function safe_me(fn, ...)
  if not M.ME then return nil end
  local f = M.ME[fn]
  if type(f) ~= "function" then return nil end
  local args = {...}
  local unpack = table.unpack or unpack
  local ok, res = pcall(function()
    return f(unpack(args))
  end)
  if not ok then return nil end
  return res
end

local function stackOf(entry)
  local ok, st = pcall(entry.getItemStack, entry)
  if ok and type(st) == "table" then return st end
  return nil
end

local function modFromName(name)
  if not name then return "unknown" end
  local i = name:find(":")
  if not i or i <= 1 then return "unknown" end
  return name:sub(1, i-1)
end

local function lower(s)
  local ok, u = pcall(require, "unicode")
  if ok and u and u.lower then return u.lower(tostring(s or "")) end
  return tostring(s or ""):lower()
end

local function matchSub(hay, needle)
  if not needle or needle == "" then return true end
  hay, needle = lower(hay), lower(needle)
  return hay:find(needle, 1, true) ~= nil
end

-- clientQuery: строка поиска; modWhitelist: множество modid=>true (или nil)
function M.get_craftables(clientQuery, modWhitelist)
  local out = {}
  if not M.ME then return out end

  local filter = (clientQuery and clientQuery ~= "") and { label = clientQuery } or nil
  local raw = safe_me("getCraftables", filter) or {}

  for i=1,#raw do
    local entry = raw[i]
    local st = stackOf(entry) or {}
    local label = st.label or st.name or "<?>"
    local name  = st.name
    local modid = modFromName(name)

    if (not modWhitelist) or modWhitelist[modid] then
      if matchSub(label, clientQuery) then
        out[#out+1] = {
          entry  = entry,
          label  = label,
          name   = name,
          damage = st.damage,
          mod    = modid
        }
      end
    end
  end
  return out
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
  local cpus = safe_me("getCpus") or safe_me("getCraftingCPUs") or {}
  local list, busy = {}, 0
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
  if not (M.ME and craft_row) then return { ok=false, err="no ME or item" } end
  local name, dmg, label = craft_row.name, craft_row.damage, craft_row.label
  local inNetCount, craftable = 0, false

  local items = safe_me("getItemsInNetwork", { name = name, damage = dmg })
  if type(items)=="table" and items[1] then
    local it = items[1]
    inNetCount = it.size or 0
    craftable  = not not (it.isCraftable or it.is_craftable)
  else
    local all = safe_me("getItemsInNetwork") or {}
    for _,it in ipairs(all) do
      local lbl = lower(it.label or it.name or "")
      if lbl == lower(label or "") then
        inNetCount = it.size or 0
        craftable  = not not (it.isCraftable or it.is_craftable)
        break
      end
    end
  end

  return {
    ok=true,
    label=label, name=name, damage=dmg,
    inNetwork=inNetCount,
    craftable=craftable,
  }
end

function M.get_jobs()
  local jobs = safe_me("getCraftingJobs") or {}
  return type(jobs)=="table" and jobs or {}
end

function M.cancel_job(id)
  if not M.ME then return false, "no ME" end
  local ok, res = pcall(function()
    if M.ME.cancelJob then return M.ME.cancelJob(id) end
    return false
  end)
  if not ok then return false, res end
  return res == true, res
end

return M

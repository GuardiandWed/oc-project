-- /home/craft_model.lua
local component = require("component")

local M = {}
M.ME = component.isAvailable("me_controller") and component.me_controller or nil

local function safe_me(fn, ...)
  if not M.ME then return nil end
  local ok, res = pcall(function() return M.ME[fn](...) end)
  if not ok then return nil end
  return res
end

local function _raw_craftables(filter)
  return safe_me("getCraftables", filter) or {}
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

local function _match(hay, needle)
  if not needle or needle == "" then return true end
  hay    = tostring(hay or ""):lower()
  needle = tostring(needle):lower()
  return hay:find(needle, 1, true) ~= nil
end

function M.get_craftables(query)
  local result = {}
  if not M.ME then return result end
  local filter = (query and query ~= "") and { label = query } or nil
  local raw = _raw_craftables(filter)

  for i = 1, #raw do
    local entry = raw[i]
    local st = _stackOf(entry) or {}
    local label = st.label or st.name or "<?>"
    if _match(label, query) then
      result[#result+1] = {
        entry  = entry,
        label  = label,
        name   = st.name,
        damage = st.damage,
        mod    = _modFromName(st.name),
      }
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
  if not M.ME then return { ok=false, err="no ME" } end
  local label = craft_row and craft_row.label
  local name  = craft_row and craft_row.name
  local dmg   = craft_row and craft_row.damage

  local inNetCount, craftable = 0, false
  local items = safe_me("getItemsInNetwork", { name = name, damage = dmg })
  if type(items)=="table" and items[1] then
    local it = items[1]
    inNetCount = it.size or 0
    craftable  = not not (it.isCraftable or it.is_craftable)
  else
    local all = safe_me("getItemsInNetwork") or {}
    for _,it in ipairs(all) do
      local lbl = (it.label or it.name or ""):lower()
      if lbl == (label or ""):lower() then
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
    return false, "cancel not supported"
  end)
  if not ok then return false, res end
  return res == true, res
end

return M

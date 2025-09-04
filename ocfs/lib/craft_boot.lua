-- /home/craft_boot.lua
-- Heavy preloader for ME cache (mods + craftables) with nice progress UI.

local component = require("component")
local event     = require("event")
local term      = require("term")
local unicode   = require("unicode")

local gpu = assert(component.gpu, "GPU required")

-- цвета
local COL_BG     = 0x0A0F0A
local COL_FRAME  = 0x0F1F0F
local COL_TEXT   = 0xDDFFDD
local COL_DIM    = 0x99CC99
local COL_WARN   = 0xFFD37F
local COL_ERR    = 0xFF6B6B
local COL_OK     = 0x7CFF7C
local COL_BARBG  = 0x123312
local COL_BAR    = 0x22FF88

local sw, sh = gpu.getResolution()
local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()

local function safeBG(c) gpu.setBackground(c) end
local function safeFG(c) gpu.setForeground(c) end
local function fill(x,y,w,h,bg) safeBG(bg); gpu.fill(x,y,w,h," ") end
local function text(x,y,str,fg) if fg then safeFG(fg) end; gpu.set(x,y,str) end
local function centerX(w) return math.max(1, math.floor((sw - w)/2)+1) end
local function centerY(h) return math.max(1, math.floor((sh - h)/2)+1) end

local function frame(x,y,w,h)
  safeFG(COL_DIM)
  gpu.set(x,y,       "┌"..string.rep("─",math.max(0,w-2)).."┐")
  for i=1,math.max(0,h-2) do gpu.set(x,y+i,"│"..string.rep(" ",math.max(0,w-2)).."│") end
  gpu.set(x,y+h-1,   "└"..string.rep("─",math.max(0,w-2)).."┘")
end

local function progressBar(x,y,w,ratio)
  local full = math.max(0, math.min(w, math.floor(w*ratio)))
  safeBG(COL_BARBG); gpu.fill(x,y,w,1," ")
  safeBG(COL_BAR);   gpu.fill(x,y,full,1," ")
  safeBG(COL_BG)
end

local function shorten(str,maxLen)
  if unicode.len(str or "") <= maxLen then return str end
  return unicode.sub(str,1,maxLen-3).."..."
end

local W, H = 70, 22
if sw < W+2 then W = math.max(40, sw-2) end
if sh < H+2 then H = math.max(18, sh-2) end
local X, Y = centerX(W), centerY(H)

local function drawChrome(title)
  term.clear()
  safeBG(COL_BG); fill(1,1,sw,sh,COL_BG)
  fill(X,Y,W,H,COL_FRAME); frame(X,Y,W,H)
  text(X+2, Y, "┤ "..(title or "Loader").." ├", COL_TEXT)
  text(X+2, Y+2, "Status:",   COL_DIM)
  text(X+2, Y+6, "Progress:", COL_DIM)
  text(X+2, Y+9, "Log:",      COL_DIM)
  fill(X+2, Y+7, W-4, 1, COL_BARBG)
end

local function writeStatus(msg, color)
  fill(X+2, Y+3, W-4, 2, COL_FRAME)
  text(X+2, Y+3, shorten(msg or "", W-6), color or COL_TEXT)
end

local logTop, logHeight = Y+10, H-11
local logLines = {}
local function log(msg, color)
  color = color or COL_TEXT
  if #logLines >= logHeight then table.remove(logLines,1) end
  table.insert(logLines, shorten(msg or "", W-6))
  for i=1,logHeight do
    fill(X+2, logTop+i-1, W-4, 1, COL_FRAME)
    local ln = logLines[i]
    if ln then text(X+2, logTop+i-1, ln, color) end
  end
end

local spinner = {"⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"}
local spinIdx = 1
local function tickSpinner()
  local s = spinner[spinIdx]; spinIdx = spinIdx % #spinner + 1
  text(X+W-4, Y+3, s, COL_DIM)
end

-- построение кешей
local function buildCaches()
  local ME = component.isAvailable("me_controller") and component.me_controller or nil
  local modsSet, modsArr = {}, {}
  local craftCache = { rows = {}, byMod = {}, built = false }

  -- 1) Моды + список всех предметов
  writeStatus("Сканирование сети ME для списка модов…", COL_DIM); tickSpinner()
  local ok1, items = pcall(function() return ME and ME.getItemsInNetwork() or {} end)
  if not ok1 or type(items) ~= "table" then items = {} end
  local total1 = #items
  for i=1,total1 do
    local it = items[i] or {}
    local name = it.name or (it.item and it.item.name)
    if type(name)=="string" then
      local p = name:find(":")
      if p and p>1 then
        local mod = name:sub(1,p-1)
        if mod and not modsSet[mod] then modsSet[mod]=true; modsArr[#modsArr+1]=mod end
      end
    end
    if (i%200)==0 or i==total1 then
      progressBar(X+2, Y+7, W-4, (total1==0 and 1 or i/total1))
      text(X+2, Y+8, ("Progress: %d%%  Mods: %d"):format(total1==0 and 100 or math.floor(i*100/total1), #modsArr), COL_DIM)
      tickSpinner()
    end
  end
  table.sort(modsArr)
  log("Найдено модов: "..tostring(#modsArr), COL_OK)

  -- индекс локализованных меток
  local labelByKey = {}
  for i = 1, total1 do
    local it = items[i] or {}
    if it.name and it.label then
      labelByKey[it.name .. ":" .. tostring(it.damage or 0)] = it.label
    end
  end

  local function goodLabel(lbl)
    if not lbl or lbl=="" or lbl=="<?>" then return false end
    if lbl=="tile.null.name" or lbl=="item.null.name" then return false end
    if lbl:match("^tile%.[%w_]+%.name$") then return false end
    if lbl:match("^item%.[%w_]+%.name$") then return false end
    return true
  end

  -- 2) Собираем все крафты
  writeStatus("Загрузка всех крафтов из ME…", COL_TEXT); tickSpinner()

  -- возьмём из инвентаря только крафтабельные позиции
  local craftableList = {}
  for i=1,total1 do
    local it = items[i] or {}
    if it.isCraftable or it.is_craftable then
      craftableList[#craftableList+1] = { name = it.name, damage = it.damage }
    end
  end

  local total2 = #craftableList
  for i=1,total2 do
    local f = craftableList[i]

    -- резолв entry: exact name+damage -> name only
    local entry
    do
      local okE1, t1 = pcall(function() return ME.getCraftables({ name=f.name, damage=f.damage }) end)
      if okE1 and type(t1)=="table" and t1[1] then entry = t1[1] end
      if not entry then
        local okE2, t2 = pcall(function() return ME.getCraftables({ name=f.name }) end)
        if okE2 and type(t2)=="table" and t2[1] then entry = t2[1] end
      end
    end

    -- stack, чтобы уточнить мод/лейбл
    local st = {}
    if entry and entry.getItemStack then
      local okS, stack = pcall(entry.getItemStack, entry)
      if okS and type(stack)=="table" then st = stack end
    end

    local name  = st.name   or f.name
    local dmg   = st.damage or f.damage
    local key   = (name or "") .. ":" .. tostring(dmg or 0)
    local label = labelByKey[key] or st.label or name or "<?>"

    local mod = "unknown"
    if type(name)=="string" then
      local p = name:find(":"); if p and p>1 then mod = name:sub(1,p-1) end
    end

    if goodLabel(label) then
      local row = { entry=entry, label=label, name=name, damage=dmg, mod=mod }
      craftCache.rows[#craftCache.rows+1] = row
      local bucket = craftCache.byMod[mod]; if not bucket then bucket={} ; craftCache.byMod[mod]=bucket end
      bucket[#bucket+1] = row
    end

    if (i%50)==0 or i==total2 then
      progressBar(X+2, Y+7, W-4, (total2==0 and 1 or i/total2))
      text(X+2, Y+8, ("Progress: %d%%  Craftables: %d/%d"):format(total2==0 and 100 or math.floor(i*100/total2), i, total2), COL_DIM)
      if label and goodLabel(label) then log("Крафт: "..shorten(label, 52), COL_TEXT) end
      tickSpinner()
    end
  end

  craftCache.built = true
  log("Готово. Всего крафтов: "..tostring(#craftCache.rows), COL_OK)

  return modsArr, craftCache
end

local M = {}

function M.run(title)
  local okRun, mods, cache
  local okExec, err = pcall(function()
    drawChrome(title or "ME Cache Builder")
    writeStatus("Инициализация…", COL_DIM)
    mods, cache = buildCaches()
    writeStatus("Кеш построен. Моды: "..tostring(#mods).."  Крафтов: "..tostring(#(cache.rows or {})), COL_OK)
  end)

  for _=1,12 do tickSpinner(); os.sleep(0.02) end
  safeBG(oldBG); safeFG(oldFG); term.clear()

  if okExec then
    return true, mods or {}, cache or { rows={}, byMod={}, built=true }
  else
    io.stderr:write("Cache builder error: "..tostring(err).."\n")
    return false, {}, { rows={}, byMod={}, built=false }
  end
end

return M

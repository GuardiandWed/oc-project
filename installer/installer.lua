

------------------------------------------

------------------------------------------
local OWNER  = "GuardiandWed"  -- напр.: "lunahale"
local REPO   = "oc-project"         -- напр.: "oc-project"
local BRANCH = "main"                 -- "main" или "dev"
local BASE   = "ocfs"                 -- папка в репо, разворачиваемая в / ("/" на OC)
local CLEAN_REMOVED = false           -- true: удалять файлы, которых нет в манифесте
local GITHUB_TOKEN = nil              -- по желанию: "ghp_xxx..." (для приватных репо/лимитов)

-- Путь самого установщика (для self-update — можно не трогать)
local SELF_PATH = "/usr/bin/oc_install.lua"

------------------------------------------
-- 2) ИМПОРТ БИБЛИОТЕК
------------------------------------------
local component = require("component")
local computer  = require("computer")
local event     = require("event")
local fs        = require("filesystem")
local term      = require("term")
local unicode   = require("unicode")

local hasGPU = component.isAvailable("gpu")
local gpu = hasGPU and component.gpu or nil
local inet = component.isAvailable("internet") and component.internet or nil

------------------------------------------
-- 3) ПОДГОТОВКА ПАПОК/ЛОГОВ/ЦВЕТОВ
------------------------------------------
local APP_DIR = "/var/oc-installer"
local LOG_DIR = APP_DIR.."/logs"
local LOCAL_MANIFEST = string.format("%s/%s_%s_%s.manifest.lua", APP_DIR, OWNER, REPO, BRANCH)

local palette = {
  bg   = 0x101114,
  panel= 0x17191D,
  border=0x23262B,
  text = 0xE6E6E6,
  dim  = 0x9AA0A6,
  accent = 0x7C5BFF,   -- фиолетовый акцент
  accent2= 0x00C896,   -- бирюзовый акцент
  barB = 0x2A2F36,
  barF = 0x00C896,
  warn = 0xFFD166,
  err  = 0xEF476F,
  ok   = 0x06D6A0
}

local function mkpath(p) if not fs.exists(p) then fs.makeDirectory(p) end end
mkpath(APP_DIR); mkpath(LOG_DIR)

local function nowstamp()
  local u = computer.uptime()
  return string.format("%08.2f", u)
end

------------------------------------------
-- 4) ПРОСТОЙ ЛОГГЕР (на экран + в файл)
------------------------------------------
local logfile = string.format("%s/%s.log", LOG_DIR, os.date and os.date("%Y%m%d-%H%M%S") or "session")
local function writeFile(path, data)
  local dir = path:match("(.+)/[^/]+$"); if dir and not fs.exists(dir) then fs.makeDirectory(dir) end
  local f, e = io.open(path, "ab"); if not f then return nil, e end
  f:write(data); f:close(); return true
end

local logLines, maxLogLines = {}, 500
local function log(line)
  local s = string.format("[%s] %s", nowstamp(), tostring(line))
  table.insert(logLines, s)
  if #logLines > maxLogLines then table.remove(logLines, 1) end
  writeFile(logfile, s.."\n")
end

------------------------------------------
-- 5) ЧТЕНИЕ КОНФИГА ИЗ /etc/oc-installer/config.lua (необязательно)
------------------------------------------
local function tryLoadConfig()
  local path = "/etc/oc-installer/config.lua"
  if not fs.exists(path) then return end
  local f = io.open(path, "rb"); if not f then return end
  local s = f:read("*a"); f:close()
  local chunk = load(s, "="..path, "t", {})
  local ok, cfg = pcall(chunk)
  if ok and type(cfg)=="table" then
    OWNER  = cfg.owner  or OWNER
    REPO   = cfg.repo   or REPO
    BRANCH = cfg.branch or BRANCH
    BASE   = cfg.base   or BASE
    CLEAN_REMOVED = (cfg.clean_removed~=nil) and cfg.clean_removed or CLEAN_REMOVED
    GITHUB_TOKEN = cfg.token or GITHUB_TOKEN
    log("Конфиг загружен из "..path)
  end
end
tryLoadConfig()

------------------------------------------
-- 6) UI/GUI РИСОВАЛКА
------------------------------------------
local W,H, oldW,oldH = 80,25, nil,nil
local animTick = 0
local spinner = {"⠋","⠙","⠸","⠴","⠦","⠇"} -- мягкая анимация
local spinIdx = 1
local statusText = "Готово."
local progressCur, progressTotal = 0, 1
local bytesCur, bytesTotal = 0, 1
local logsScroll = 0  -- 0 = авто-прокрутка

local function setColor(bg, fg)
  if not hasGPU then return end
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
end

local function drawBox(x,y,w,h, colBorder, colFill)
  if not hasGPU then return end
  setColor(colFill or palette.panel, palette.text)
  gpu.fill(x,y,w,h," ")
  setColor(colBorder or palette.border, palette.text)
  -- рамка
  for i=x, x+w-1 do gpu.set(i, y, "─"); gpu.set(i, y+h-1, "─") end
  for j=y, y+h-1 do gpu.set(x, j, "│"); gpu.set(x+w-1, j, "│") end
  gpu.set(x, y, "┌"); gpu.set(x+w-1, y, "┐")
  gpu.set(x, y+h-1, "└"); gpu.set(x+w-1, y+h-1, "┘")
end

local function ui_init()
  if not hasGPU then
    io.write("Нет GPU/экрана: используем текстовый режим логов.\n")
    return
  end
  oldW,oldH = gpu.getResolution()
  local maxW, maxH = gpu.maxResolution()
  W = math.min(100, maxW); H = math.min(30, maxH)
  gpu.setResolution(W,H)
  setColor(palette.bg, palette.text); gpu.fill(1,1,W,H," ")

  -- Верхняя плашка
  setColor(palette.accent, 0x000000); gpu.fill(1,1,W,3," ")
  setColor(nil, 0x000000)
  local title = " OpenComputers GitHub Installer "
  local repoStr = string.format(" %s/%s (%s) base: /%s ", OWNER, REPO, BRANCH, BASE)
  gpu.set(math.floor(W/2 - unicode.len(title)/2), 2, title)
  setColor(palette.accent2, 0x000000)
  gpu.set(math.floor(W/2 - unicode.len(repoStr)/2), 1, repoStr)

  -- Области
  drawBox(2,4, W-3, 9, palette.border, palette.panel)         -- статус + прогресс
  drawBox(2,14, W-3, H-16, palette.border, palette.panel)     -- логи

  -- подсказки
  setColor(nil, palette.dim)
  gpu.set(3,H-1, "Q — выход  |  PgUp/PgDn — прокрутка логов  |  C — clean removed: "..tostring(CLEAN_REMOVED))
end

local function ui_done()
  if hasGPU and oldW and oldH then gpu.setResolution(oldW,oldH) end
end

local function ui_status(text)
  statusText = text or ""
  log(text)
end

local function ui_redraw()
  if not hasGPU then return end
  -- топовая анимация плашки (мягкая волна оттенков)
  animTick = animTick + 1
  if animTick % 2 == 0 then
    local wave = (animTick % 20) / 20
    local col = palette.accent
    -- простая "переливка": слегка меняем яркость
    local function shade(c, k)
      local r = bit32.rshift(bit32.band(c,0xFF0000),16)
      local g = bit32.rshift(bit32.band(c,0x00FF00),8)
      local b = bit32.band(c,0x0000FF)
      r = math.min(255, math.max(0, math.floor(r*(0.85+0.15*k))))
      g = math.min(255, math.max(0, math.floor(g*(0.85+0.15*k))))
      b = math.min(255, math.max(0, math.floor(b*(0.85+0.15*k))))
      return bit32.lshift(r,16)+bit32.lshift(g,8)+b
    end
    setColor(shade(palette.accent, wave), 0x000000); gpu.fill(1,1,W,1," ")
    setColor(shade(palette.accent2, 1-wave), 0x000000); gpu.fill(1,2,W,1," ")
  end

  -- статусная строка + спиннер
  local s = statusText
  local spin = spinner[spinIdx]; spinIdx = spinIdx % #spinner + 1
  setColor(palette.panel, palette.text); gpu.fill(3,5, W-6,1," ")
  setColor(nil, palette.text)
  local statusShown = ("  %s  %s"):format(spin, s)
  gpu.set(3,5, unicode.sub(statusShown,1,W-6))

  -- прогресс-бар
  local barX, barY, barW = 3, 8, W-6
  setColor(palette.barB, 0x000000); gpu.fill(barX,barY, barW,1, " ")
  local perc = (progressTotal>0) and (progressCur/progressTotal) or 0
  local filled = math.floor(barW * perc)
  setColor(palette.barF, 0x000000); gpu.fill(barX,barY, math.max(0, math.min(barW,filled)),1, " ")
  -- блик (анимация «перелива»)
  local hlPos = (animTick % (barW+10))-10
  if hlPos>0 and hlPos<=barW then
    setColor(0xFFFFFF, 0x000000); gpu.set(barX+hlPos, barY, " ")
  end
  setColor(nil, palette.dim)
  local ptxt = string.format("%d/%d  |  %.1f%%  |  %d KB / %d KB",
    math.min(progressCur,progressTotal), progressTotal, perc*100, math.floor(bytesCur/1024), math.max(1, math.floor(bytesTotal/1024)))
  gpu.set(math.floor(W/2 - unicode.len(ptxt)/2), 9, ptxt)

  -- окно логов (последние строки с возможностью скролла)
  local lx,ly,lw,lh = 3, 15, W-6, H-18
  setColor(palette.panel, palette.text); gpu.fill(lx,ly,lw,lh," ")
  local visible = lh
  local start = math.max(1, #logLines - visible - logsScroll + 1)
  for i=0, visible-1 do
    local line = logLines[start+i]
    if line then
      setColor(nil, palette.dim)
      gpu.set(lx, ly+i, unicode.sub(line,1,lw))
    end
  end
end

------------------------------------------
-- 7) HTTP ПОТОКОВОЕ СКАЧИВАНИЕ (для анимаций)
------------------------------------------
local function http_open(url, headers)
  if not inet then return nil, "Нет интернет-карты" end
  headers = headers or {["User-Agent"]="OC-Installer"}
  if GITHUB_TOKEN then headers["Authorization"] = "token "..GITHUB_TOKEN end
  local ok, handle = pcall(inet.request, url, nil, headers)
  if not ok or not handle then return nil, "HTTP request failed" end
  return handle
end

local function http_download(url, onChunk)
  local h, e = http_open(url)
  if not h then return nil, e end
  local total = 0
  while true do
    local data, reason = h.read()
    if data then
      total = total + #data
      if onChunk then onChunk(data) end
    elseif reason then
      return nil, reason
    else
      break
    end
    -- даём UI «подышать»
    ui_redraw(); event.pull(0.02)
  end
  return total
end

------------------------------------------
-- 8) МАНИФЕСТЫ (удалённый и локальный)
------------------------------------------
local function raw_url(path)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", OWNER, REPO, BRANCH, path)
end

local function load_remote_manifest()
  ui_status("Скачиваю манифест...")
  local body = {}
  local url = raw_url("oc_manifest.lua")
  local ok, err = http_download(url, function(chunk) table.insert(body, chunk) end)
  if not ok and err then return nil, "Не удалось получить манифест: "..tostring(err) end
  local s = table.concat(body)
  local chunk, lerr = load(s, "=oc_manifest.lua", "t", {})
  if not chunk then return nil, "Ошибка парсинга манифеста: "..tostring(lerr) end
  local ok2, t = pcall(chunk)
  if not ok2 or type(t)~="table" or type(t.files)~="table" then
    return nil, "Некорректный формат манифеста"
  end
  return t
end

local function read_lua_table(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close()
  local chunk, err = load(s, "="..path, "t", {})
  if not chunk then return nil, err end
  local ok, res = pcall(chunk)
  if not ok or type(res)~="table" then return nil, "not a table" end
  return res
end

local function load_local_manifest()
  if not fs.exists(APP_DIR) then fs.makeDirectory(APP_DIR) end
  return read_lua_table(LOCAL_MANIFEST) or { files = {} }
end

local function save_local_manifest(t)
  local f = io.open(LOCAL_MANIFEST, "wb"); if not f then return end
  f:write("return { files = {\n")
  for _,it in ipairs(t.files) do
    f:write(string.format('  {["path"]="%s",["sha"]="%s",["size"]=%d},\n', it.path, it.sha, it.size or 0))
  end
  f:write("}}\n"); f:close()
end

------------------------------------------
-- 9) УТИЛИТЫ ФАЙЛОВ
------------------------------------------
local function ensure_dir(path)
  local dir = path:match("(.+)/[^/]+$") or "/"
  if not fs.exists(dir) then fs.makeDirectory(dir) end
end

local function write_atomic(path, data_chunks)
  ensure_dir(path)
  local tmp = path..".tmp_dl"
  local f, e = io.open(tmp, "wb"); if not f then return nil, e end
  for _,ch in ipairs(data_chunks) do f:write(ch) end
  f:close()
  if fs.exists(path) then fs.remove(path) end
  fs.rename(tmp, path)
  return true
end

------------------------------------------
-- 10) ОСНОВНАЯ ЛОГИКА УСТАНОВКИ
------------------------------------------
local function build_tasks(remote, localM)
  local idxRemote, idxLocal = {}, {}
  for _,it in ipairs(remote.files) do idxRemote[it.path]=it end
  for _,it in ipairs(localM.files) do idxLocal[it.path]=it end

  local tasks, toDelete, totalBytes = {}, {}, 0
  for path,it in pairs(idxRemote) do
    if path:sub(1, #BASE+1)==(BASE.."/") then
      local target = "/"..path:sub(#BASE+2)
      local need = true
      if idxLocal[path] and idxLocal[path].sha == it.sha then
        need = false
      end
      table.insert(tasks, {path=path, target=target, sha=it.sha, size=it.size or 0, need=need})
      if need then totalBytes = totalBytes + (it.size or 0) end
    end
  end

  if CLEAN_REMOVED then
    for path,_ in pairs(idxLocal) do
      if path:sub(1,#BASE+1)==(BASE.."/") and not idxRemote[path] then
        local target = "/"..path:sub(#BASE+2)
        table.insert(toDelete, target)
      end
    end
  end

  table.sort(tasks, function(a,b) return a.path < b.path end)
  return tasks, toDelete, totalBytes
end

local function install()
  ui_init()
  ui_status("Готовлюсь к установке...")
  ui_redraw()

  local remote, err = load_remote_manifest()
  if not remote then ui_status(err); ui_redraw(); return false end
  local localM = load_local_manifest()

  local tasks, toDelete, totalBytes = build_tasks(remote, localM)
  local needed = 0; for _,t in ipairs(tasks) do if t.need then needed=needed+1 end end

  progressCur, progressTotal = 0, math.max(1, needed)
  bytesCur, bytesTotal = 0, math.max(1, totalBytes)

  if needed == 0 then
    ui_status("Всё актуально. Нечего обновлять."); ui_redraw()
  end

  -- скачивание изменившихся
  for _,t in ipairs(tasks) do
    if t.need then
      local url = raw_url(t.path)
      ui_status(("Скачиваю %s"):format(t.path)); ui_redraw()
      local chunks = {}
      local lastBytes = bytesCur
      local ok, reason = http_download(url, function(ch)
        table.insert(chunks, ch)
        bytesCur = lastBytes + (#table.concat(chunks))
      end)
      if not ok and reason then
        ui_status("Ошибка загрузки: "..t.path.." ("..tostring(reason)..")")
        ui_redraw(); return false
      end
      local okW, eW = write_atomic(t.target, chunks)
      if not okW then
        ui_status("Ошибка записи: "..t.target.." ("..tostring(eW)..")")
        ui_redraw(); return false
      end
      log(("OK: %s → %s"):format(t.path, t.target))
      progressCur = progressCur + 1
      bytesCur = bytesCur + (t.size or 0)
      ui_redraw()
    end
  end

  -- удаление старых (если включено)
  if CLEAN_REMOVED and #toDelete>0 then
    ui_status("Удаляю удалённые из репо файлы...")
    for _,p in ipairs(toDelete) do
      if fs.exists(p) and not fs.isDirectory(p) then
        pcall(fs.remove, p); log("Удалён: "..p)
      end
      ui_redraw(); event.pull(0.01)
    end
  end

  -- сохраняем новый локальный манифест
  save_local_manifest(remote)

  ui_status("Готово! Файлы синхронизированы.")
  ui_redraw()
  return true
end

------------------------------------------
-- 11) ОБРАБОТКА КЛАВИШ И ЗАПУСК
------------------------------------------
local function main()
  local running = true
  local ok = false

  -- фоновая отрисовка (тиктаймер)
  local function tick()
    while running do
      ui_redraw()
      event.pull(0.05)
    end
  end

  -- запускаем установку в корутине
  local co = coroutine.create(install)
  local tickCo = coroutine.create(tick)

  -- главный цикл
  while running do
    if coroutine.status(tickCo) ~= "dead" then coroutine.resume(tickCo) end
    if coroutine.status(co) ~= "dead" then
      local r, res = coroutine.resume(co)
      if coroutine.status(co)=="dead" then ok = res end
    end

    local ev = {event.pull(0.05)}
    local e = ev[1]
    if e == "key_down" then
      local _,_,_,code = table.unpack(ev)
      -- Q
      if code == 0x10 then running = false end
      -- PgUp / PgDn
      if code == 0x49 then logsScroll = math.min(#logLines, logsScroll + 3) end
      if code == 0x51 then logsScroll = math.max(0, logsScroll - 3) end
      -- C toggle clean
      if code == 0x2E then
        CLEAN_REMOVED = not CLEAN_REMOVED
        ui_status("Clean removed: "..tostring(CLEAN_REMOVED))
      end
    elseif e == "interrupted" then
      running = false
    end
  end

  ui_done()
  if ok then
    io.write("Установка завершена успешно.\n")
  else
    io.write("Установка завершена с ошибкой (см. логи: "..logfile..")\n")
  end
end

-- запуск
local ok, err = pcall(main)
if not ok then
  io.stderr:write("Критическая ошибка: "..tostring(err).."\n")
end

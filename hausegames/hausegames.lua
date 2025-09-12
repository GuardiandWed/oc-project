-- /home/hausegames.lua — UI на rcui без doubleBuffering/image

local rcui      = require("rcui")        -- важно: rcui, не reui
local event     = require("event")
local computer  = require("computer")
local component = require("component")
local gpu       = component.gpu
local unicode   = require("unicode")

local boot      = require("gamesboot")   -- boot.list_games() и boot.run(name)
local Chat      = require("chatcmd")

--------------------------------------------------------------------------------
-- ИНИЦИАЛИЗАЦИЯ UI
--------------------------------------------------------------------------------
rcui.init{
  w = 160, h = 50,
  theme  = false,   -- false=тёмная, true/"light"=светлая
  metric = 0,
}
local C = rcui.colors()

--------------------------------------------------------------------------------
-- ДАННЫЕ / СОСТОЯНИЕ
--------------------------------------------------------------------------------
local rows, cols    = 2, 3
local cardW, cardH  = 26, 11
local padX, padY    = 10, 8

local gridX, gridY  = 3, 4
local gridW         = cols*cardW + (cols-1)*padX + 10
local gridH         = rows*cardH + (rows-1)*padY + 10

local sidebarX      = gridX + gridW + 4
local sidebarW      = math.max(36, 160 - sidebarX - 3)
local sideTop       = gridY
local sideGap       = 4

local selectedIdx, selectedGame = nil, nil
local fps, framesCount = 0, 0
local memUsedStr, uptimeStr = "--", "--"

local function getGames()
  local ok, list = pcall(boot.list_games)
  return (ok and type(list)=="table") and list or {}
end
local games = getGames()

--------------------------------------------------------------------------------
-- УТИЛИТЫ РИСОВАНИЯ
--------------------------------------------------------------------------------
local function text(x,y,str,color)
  if color then local prev=gpu.getForeground(); gpu.setForeground(color); gpu.set(x,y,str or ""); gpu.setForeground(prev)
  else gpu.set(x,y,str or "") end
end
local function rect(x,y,w,h,color)
  local prev=gpu.getBackground(); if color then gpu.setBackground(color) end
  for i=0,(h or 1)-1 do gpu.fill(x,y+i,w or 1,1," ") end
  gpu.setBackground(prev)
end
local function center_x(x,w,s) return x + math.max(0, math.floor((w - unicode.len(s or ""))/2)) end
local function humanBytes(b)
  b = tonumber(b) or 0
  local u={"B","KiB","MiB","GiB","TiB"}; local i=1
  while b>=1024 and i<#u do b=b/1024; i=i+1 end
  local s=(b<10) and string.format("%.2f",b) or (b<100) and string.format("%.1f",b) or string.format("%.0f",b)
  return s:gsub("%.0$","").." "..u[i]
end

--------------------------------------------------------------------------------
-- ШАПКА
--------------------------------------------------------------------------------
rcui.createPanel(1, 1, 160, 3, function(self)
  local title = "HauseMasters"
  text(center_x(1,160,title), 2, title, C.text)
end)

--------------------------------------------------------------------------------
-- ПРАВАЯ КОЛОНКА
--------------------------------------------------------------------------------
local infoPanel = rcui.createPanel(sidebarX, sideTop, sidebarW, 14, function(self)
  text(self.x+2, self.y, "Информация", C.text)
  if selectedGame then
    text(self.x+2, self.y+2, "Название: "..(selectedGame.name or "—"), C.text)
    text(self.x+2, self.y+3, "Создано:  "..(selectedGame.created or "—"), C.text)
    text(self.x+2, self.y+4, "Сыграно:  "..(selectedGame.played_h or "—"), C.text)
    if selectedGame.desc then
      text(self.x+2, self.y+6, "Описание:", C.text)
      local maxW = math.max(10, self.w-4)
      local s = tostring(selectedGame.desc)
      if unicode.len(s) > maxW then s = unicode.sub(s,1,maxW-1).."…" end
      text(self.x+2, self.y+7, s, C.text)
    end
  else
    text(self.x+2, self.y+2, "Выбери игру слева, чтобы увидеть детали", C.text)
  end
end)

local metricsY = sideTop + 14 + sideGap
rcui.createPanel(sidebarX, metricsY, sidebarW, 6, function(self)
  text(self.x+2, self.y, "Системные метрики", C.text)
  text(self.x+2, self.y+2, ("FPS: %s    Память: %s    Uptime: %s"):format(fps or "--", memUsedStr, uptimeStr), C.text)
end)

local logHeaderY = metricsY + 6 + sideGap
rcui.createPanel(sidebarX, logHeaderY, sidebarW, 2, function(self)
  text(self.x+2, self.y, "Журнал", C.text)
end)
local logPaneY   = logHeaderY + 2
local logHeight  = (50 - 2) - logPaneY - 1
local log        = rcui.createConsole(sidebarX, logPaneY, sidebarW, math.max(4, logHeight), C.text)
local function logInfo(s) rcui.message(s, C.text) end
local function logWarn(s) rcui.message(s, C.warn) end
local function logGood(s) rcui.message(s, C.ok) end
local function logErr(s)  rcui.message(s, C.err) end
logInfo("HauseGames UI запущен")

--------------------------------------------------------------------------------
-- СЕТКА КАРТОЧЕК
--------------------------------------------------------------------------------
local grid = {}
for r=1,rows do
  grid[r]={}
  for c=1,cols do
    local x = gridX + (c-1)*(cardW+padX)
    local y = gridY + (r-1)*(cardH+padY)
    grid[r][c] = {x=x,y=y}
  end
end

local function mountCard(i, g, x, y, w, h)
  rcui.createPanel(x, y, w, h, function(self)
    -- внутренняя подложка
    rect(self.x+1, self.y+1, self.w-2, self.h-4, C.bg2)
    local name    = (g and g.name)     or "Пусто"
    local created = (g and g.created)  or "--"
    local played  = (g and g.played_h) or "--"
    text(self.x+3, self.y+2, name, C.text)
    text(self.x+3, self.y+4, "Создано: "..created, C.text)
    text(self.x+3, self.y+5, "Сыграно: "..played, C.text)
  end)

  -- выбор карточки кликом
  rcui.registerClickArea(x, y, x+w-1, y+h-1, function()
    if g then
      selectedIdx, selectedGame = i, g
      logInfo("Выбрана игра: "..(g.name or "?"))
      rcui.invalidate()
    end
  end, "card-"..tostring(i))

  rcui.button(x+4, y+h-4, w-8, 3, "Запустить", {
    color     = C.whitebtn2 or 0x38afff,
    textColor = 0x000000,
    onClick   = function()
      if not g then logWarn("Пустой слот. Добавь игру в gamesboot."); return end
      logGood("Старт игры: "..(g.name or "?"))
      local ok,err = pcall(function() require("gamesboot").run(g.name) end)
      if not ok then logErr("Ошибка запуска: "..tostring(err)) end
    end
  })
end

local function mountGrid()
  local idx=1
  for r=1,rows do
    for c=1,cols do
      local cell = grid[r][c]
      mountCard(idx, games[idx], cell.x, cell.y, cardW, cardH)
      idx = idx + 1
    end
  end
end
mountGrid()

--------------------------------------------------------------------------------
-- КНОПКИ ВНИЗУ
--------------------------------------------------------------------------------
rcui.button(4, 50-4, 30, 3, "Рестарт программы", {
  color= C.whitebtn2 or 0x38afff, textColor=0x000000,
  onClick = function() logInfo("Перезапуск…"); require("shell").execute("reboot") end
})
rcui.button(38, 50-4, 30, 3, "Выход из программы", {
  color= 0xFF7C8F, textColor=0x000000,
  onClick = function() if _G.__hg_bot then pcall(_G.__hg_bot.stop, _G.__hg_bot) end; rcui.stop() end
})
rcui.button(72, 50-4, 22, 3, "Переключить тему", {
  color= C.whitebtn2 or 0x38afff, textColor=0x000000,
  onClick = function()
    rcui.setTheme((rcui.colors().bg == 0x202020) and "light" or "dark")
    C = rcui.colors(); rcui.invalidate()
  end
})
rcui.button(96, 50-4, 24, 3, "Обновить список игр", {
  color= C.whitebtn2 or 0x38afff, textColor=0x000000,
  onClick = function()
    games = getGames(); selectedIdx, selectedGame = nil, nil
    logInfo("Список игр обновлён"); rcui.invalidate()
  end
})

--------------------------------------------------------------------------------
-- БЕГУЩАЯ СТРОКА (опционально)
--------------------------------------------------------------------------------
rcui.createMarquee(4, 3, 110, "Добро пожаловать в HauseGames • Выбирай игру слева • Удачи!   ", 0xF0B915)

--------------------------------------------------------------------------------
-- СИСТЕМНЫЕ ОБНОВЛЕНИЯ
--------------------------------------------------------------------------------
rcui.every(1.0, function()
  fps = framesCount; framesCount = 0
  local used = (computer.totalMemory() or 0) - (computer.freeMemory() or 0)
  memUsedStr = humanBytes(used)
  local up = math.floor(computer.uptime())
  local h = math.floor(up/3600); local m = math.floor((up%3600)/60); local s = up%60
  uptimeStr = string.format("%02d:%02d:%02d", h, m, s)
  rcui.invalidate()
end)

event.listen("interrupted", function() rcui.stop() end)

--------------------------------------------------------------------------------
-- ЧАТ-БОТ
--------------------------------------------------------------------------------
local bot = Chat.new{ prefix="@", name="Оператор", admins={"HauseMasters"} }
bot:start(); _G.__hg_bot = bot

--------------------------------------------------------------------------------
-- ОСНОВНОЙ ЦИКЛ
--------------------------------------------------------------------------------
rcui.run(function() framesCount = framesCount + 1 end)

-- очистка экрана после выхода
do local w,h=gpu.getResolution(); gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF); gpu.fill(1,1,w,h," ") end

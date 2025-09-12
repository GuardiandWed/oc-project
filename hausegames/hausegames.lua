-- /home/hausegames.lua — UI на rcui: красивая решётка карточек игр + правая колонка + чат-бот

local rcui      = require("rcui")
local buffer    = require("doubleBuffering")
local event     = require("event")
local computer  = require("computer")
local component = require("component")
local unicode   = require("unicode")

local boot      = require("gamesboot")  -- ожидается: boot.list_games() -> {}, boot.run(name)
local Chat      = require("chatcmd")    -- опционально: чат-бот с префиксом "@"

--------------------------------------------------------------------------------
-- ИНИЦИАЛИЗАЦИЯ UI
--------------------------------------------------------------------------------
rcui.init{
  w = 160, h = 50,
  theme = false,  -- false=тёмная, true/"light"=светлая
  bgDark  = "/home/images/hg_bg_dark.pic",
  bgLight = "/home/images/hg_bg_light.pic",
  metric  = 0,
}

local C = rcui.colors()

--------------------------------------------------------------------------------
-- ДАННЫЕ / СОСТОЯНИЕ
--------------------------------------------------------------------------------
local rows, cols    = 2, 3
local cardW, cardH  = 26, 11
local padX, padY    = 10, 8

local gridX, gridY  = 3, 4
local gridW         = cols * cardW + (cols - 1) * padX + 10
local gridH         = rows * cardH + (rows - 1) * padY + 10

local sidebarX      = gridX + gridW + 4
local sidebarW      = math.max(36, 160 - sidebarX - 3)
local sideTop       = gridY
local sideGap       = 4

local selectedIdx   = nil
local selectedGame  = nil

-- метрики
local fps           = 0
local framesCount   = 0
local memUsedStr    = "--"
local uptimeStr     = "--"

-- список игр (обновляем на старте и по F5/кнопке)
local function getGames()
  local ok, list = pcall(boot.list_games)
  if not ok or type(list) ~= "table" then return {} end
  return list
end
local games = getGames()

--------------------------------------------------------------------------------
-- УТИЛИТЫ РИСОВАНИЯ ТЕКСТА
--------------------------------------------------------------------------------
local function text(x,y,str,color) buffer.drawText(x,y,color or C.text, str or "") end

local function center_text(x, w, s) -- вернёт x-координату для центрирования строки s в рамке ширины w
  local len = unicode.len(s or "")
  return x + math.max(0, math.floor((w - len) / 2))
end

local function humanBytes(b) -- человекочитаемая память (Ki/Mi/Gi)
  b = tonumber(b) or 0
  local units = {"B","KiB","MiB","GiB","TiB"}
  local i = 1
  while b >= 1024 and i < #units do b = b / 1024; i = i + 1 end
  local s = (b < 10) and string.format("%.2f", b) or (b < 100) and string.format("%.1f", b) or string.format("%.0f", b)
  s = s:gsub("%.0$", "")
  return s .. " " .. units[i]
end

--------------------------------------------------------------------------------
-- ШАПКА
--------------------------------------------------------------------------------
rcui.createPanel(1, 1, 160, 3, function(self)
  local title = "HauseMasters"
  text(center_text(1, 160, title), 2, title, C.text)
end)

--------------------------------------------------------------------------------
-- ПРАВАЯ КОЛОНКА: ИНФО + МЕТРИКИ + ЛОГ
--------------------------------------------------------------------------------

-- Информация о выбранной игре
local infoPanel = rcui.createPanel(sidebarX, sideTop, sidebarW, 14, function(self)
  text(self.x + 2, self.y, "Информация", C.text)
  if selectedGame then
    text(self.x + 2, self.y + 2,  "Название: " .. (selectedGame.name or "—"), C.text)
    text(self.x + 2, self.y + 3,  "Создано:  " .. (selectedGame.created or "—"), C.text)
    text(self.x + 2, self.y + 4,  "Сыграно:  " .. (selectedGame.played_h or "—"), C.text)
    if selectedGame.desc then
      text(self.x + 2, self.y + 6,  "Описание:", C.text)
      -- простая обрезка по ширине
      local maxW = math.max(10, self.w - 4)
      local s = tostring(selectedGame.desc)
      local l1 = unicode.len(s)
      if l1 > maxW then s = unicode.sub(s, 1, maxW - 1) .. "…" end
      text(self.x + 2, self.y + 7, s, C.text)
    else
      text(self.x + 2, self.y + 6, "&7Выбери игру слева, чтобы увидеть детали", C.text)
    end
  else
    text(self.x + 2, self.y + 2,  "Выбери игру слева, чтобы увидеть детали", C.text)
  end
end)

-- Системные метрики
local metricsY = sideTop + 14 + sideGap
local metricsPanel = rcui.createPanel(sidebarX, metricsY, sidebarW, 6, function(self)
  text(self.x + 2, self.y, "Системные метрики", C.text)
  text(self.x + 2, self.y + 2,
       ("FPS: %s    Память: %s    Uptime: %s"):format(fps or "--", memUsedStr, uptimeStr),
       C.text)
end)

-- Журнал: заголовок + консоль ниже
local logHeaderY = metricsY + 6 + sideGap
rcui.createPanel(sidebarX, logHeaderY, sidebarW, 2, function(self)
  text(self.x + 2, self.y, "Журнал", C.text)
end)
local logPaneY = logHeaderY + 2
local logHeight = (50 - 2) - logPaneY - 1
local log = rcui.createConsole(sidebarX, logPaneY, sidebarW, math.max(4, logHeight), C.text)

local function logInfo(s) rcui.message(s, C.text) end
local function logWarn(s) rcui.message(s, C.warn) end
local function logGood(s) rcui.message(s, C.ok) end
local function logErr(s)  rcui.message(s, C.err) end

logInfo("HauseGames UI запущен")

--------------------------------------------------------------------------------
-- СЕТКА КАРТОЧЕК ИГР
--------------------------------------------------------------------------------
local grid = {}
for r = 1, rows do
  grid[r] = {}
  for c = 1, cols do
    local x = gridX + (c - 1) * (cardW + padX)
    local y = gridY + (r - 1) * (cardH + padY)
    grid[r][c] = {x = x, y = y}
  end
end

local function mountCard(i, g, x, y, w, h)
  -- сама «карта»
  rcui.createPanel(x, y, w, h, function(self)
    buffer.drawRectangle(self.x + 1, self.y + 1, self.w - 2, self.h - 4, C.bg2, 0, " ")
    local name    = (g and g.name) or "Пусто"
    local created = (g and g.created) or "--"
    local played  = (g and g.played_h) or "--"

    text(self.x + 3, self.y + 2, name, C.text)
    text(self.x + 3, self.y + 4, "Создано: " .. created, C.text)
    text(self.x + 3, self.y + 5, "Сыграно: " .. played, C.text)
  end)

  -- выбор карточки по клику по области карты
  rcui.registerClickArea(x, y, x + w - 1, y + h - 1, function()
    if g then
      selectedIdx  = i
      selectedGame = g
      logInfo("Выбрана игра: " .. (g.name or "?"))
      rcui.invalidate()
    end
  end, "card-"..tostring(i))

  -- кнопка "Запустить"
  rcui.button(x + 4, y + h - 4, w - 8, 3, "Запустить", {
    color   = C.whitebtn2 or 0x38afff,
    textColor = 0x000000,
    onClick = function()
      if not g then
        logWarn("Пустой слот. Добавь игру в gamesboot.")
        return
      end
      logGood("Старт игры: " .. (g.name or "?"))
      local ok, err = pcall(function() require("gamesboot").run(g.name) end)
      if not ok then logErr("Ошибка запуска: "..tostring(err)) end
    end
  })
end

-- отрисовываем карточки из текущего списка
local function mountGrid()
  local idx = 1
  for r = 1, rows do
    for c = 1, cols do
      local cell = grid[r][c]
      mountCard(idx, games[idx], cell.x, cell.y, cardW, cardH)
      idx = idx + 1
    end
  end
end
mountGrid()

--------------------------------------------------------------------------------
-- НИЖНИЕ КНОПКИ (footer)
--------------------------------------------------------------------------------
local function restart_program()
  logInfo("Перезапуск программы…")
  require("shell").execute("reboot")
end

rcui.button(4, 50 - 4, 30, 3, "Рестарт программы", {
  color     = C.whitebtn2 or 0x38afff,
  textColor = 0x000000,
  onClick   = restart_program
})

rcui.button(38, 50 - 4, 30, 3, "Выход из программы", {
  color     = 0xFF7C8F,
  textColor = 0x000000,
  onClick   = function()
    if _G.__hg_bot then pcall(_G.__hg_bot.stop, _G.__hg_bot) end
    rcui.stop()
  end
})

-- Переключение темы (приятный бонус)
rcui.button(72, 50 - 4, 22, 3, "Переключить тему", {
  color     = C.whitebtn2 or 0x38afff,
  textColor = 0x000000,
  onClick   = function()
    rcui.setTheme(rcui.colors() == C and "light" or "dark")
    -- переснять ссылку на актуальные цвета
    C = rcui.colors()
    rcui.invalidate()
  end
})

-- Обновить список игр (на лету)
rcui.button(96, 50 - 4, 24, 3, "Обновить список игр", {
  color     = C.whitebtn2 or 0x38afff,
  textColor = 0x000000,
  onClick   = function()
    games = getGames()
    selectedIdx, selectedGame = nil, nil
    logInfo("Список игр обновлён")
    rcui.invalidate()
  end
})

--------------------------------------------------------------------------------
-- БЕГУЩАЯ СТРОКА (опционально, можно убрать)
--------------------------------------------------------------------------------
local mq = rcui.createMarquee(4, 3, 110, "Добро пожаловать в HauseGames • Выбирай игру слева • Удачи!   ", 0xF0B915)

--------------------------------------------------------------------------------
-- СИСТЕМНЫЕ ОБНОВЛЕНИЯ
--------------------------------------------------------------------------------
-- обновление FPS/памяти/аптайма
rcui.every(1.0, function()
  fps = framesCount; framesCount = 0
  local used = (computer.totalMemory() or 0) - (computer.freeMemory() or 0)
  memUsedStr = humanBytes(used)
  local up = math.floor(computer.uptime())
  local h = math.floor(up / 3600); local m = math.floor((up % 3600) / 60); local s = up % 60
  uptimeStr = string.format("%02d:%02d:%02d", h, m, s)
  rcui.invalidate()
end)

-- аккуратный выход по Ctrl+Alt+C
event.listen("interrupted", function()
  logWarn("Получено прерывание, выходим…")
  rcui.stop()
end)

--------------------------------------------------------------------------------
-- ЧАТ-БОТ (если нужен)
--------------------------------------------------------------------------------
local bot = Chat.new{ prefix="@", name="Оператор", admins={"HauseMasters"} }
bot:start()
_G.__hg_bot = bot

--------------------------------------------------------------------------------
-- ОСНОВНОЙ ЦИКЛ
--------------------------------------------------------------------------------
rcui.run(function()
  -- Лёгкий счётчик FPS: сколько итераций за секунду
  framesCount = framesCount + 1
end)

-- после выхода — очищаем экран
require("component").gpu.setBackground(0x000000); require("component").gpu.setForeground(0xFFFFFF)
local w,h = require("component").gpu.getResolution()
require("component").gpu.fill(1,1,w,h," ")

-- /home/hausegames.lua — Меню игр в стиле «как у друга»
local fs       = require("filesystem")
local unicode  = require("unicode")
local rcui     = require("rcui")

-- настройка темы и фонов (поставь свои .pic если есть)
rcui.init{
  w = 160, h = 50,
  theme  = "dark",
  bgDark = "/home/images/reactorGUI.pic",
  bgLight= "/home/images/reactorGUI_white.pic",
}

-- ============================================================================

-- где лежат игры (любой из вариантов)
local GAME_DIRS = { "/home/games", "/usr/games", "/games" }

-- что считаем «игрой»
local ENTRY_FILES = { "main.lua", "run.lua", "game.lua" }

-- простая БД «сыграно» (можешь заменить на свою)
local DATA_DIR   = "/home/data"
local STATS_FILE = DATA_DIR .. "/games_stats.lua"

local state = {
  games = {},          -- { {id,title,path,created,played= "MM:SS", sessions=0}, ... }
  selection = nil,     -- индекс выбранной игры
  page = 1,
  perPage = 6,
  sortMode = "az",     -- "az" | "date"
}

-- ===== утилиты даты/времени ==================================================
local function fmtDate(ts)
  if not ts then return "--" end
  local d = math.floor(ts/86400000)  -- OC возвращает ms от эпохи (обычно)
  local s = os.date("*t", math.floor(ts/1000))
  if s then
    return string.format("%04d-%02d-%02d", s.year, s.month, s.day)
  else
    return tostring(ts)
  end
end

local function fmtPlayed(sec)
  if not sec then return "--:--" end
  local m = math.floor(sec/60)
  local s = math.floor(sec%60)
  return string.format("%02d:%02d", m, s)
end

-- ===== загрузка/сохранение статистики =======================================
local function loadStats()
  local ok, data = pcall(dofile, STATS_FILE)
  if ok and type(data)=="table" then return data end
  return {}
end

local function saveStats(tbl)
  fs.makeDirectory(DATA_DIR)
  local f = io.open(STATS_FILE, "wb")
  if not f then return end
  f:write("return " .. require("serialization").serialize(tbl))
  f:close()
end

local stats = loadStats()

-- ===== поиск игр на диске ====================================================
local function isGamePath(path)
  if fs.isDirectory(path) then
    for _,f in ipairs(ENTRY_FILES) do
      if fs.exists(fs.concat(path, f)) then return true end
    end
  else
    -- одиночный .lua в корне каталога игр тоже считаем игрой
    if path:match("%.lua$") then return true end
  end
  return false
end

local function scanGames()
  local res = {}
  for _,root in ipairs(GAME_DIRS) do
    if fs.exists(root) then
      for item in fs.list(root) do
        local p = fs.concat(root, item)
        if isGamePath(p) then
          local id = (item:gsub("%.lua$",""))
          local title = id
          local created = fs.lastModified(p) or os.time()*1000
          local st = stats[id] or {}
          table.insert(res, {
            id = id,
            title = title,
            path = p,
            created = created,
            played = st.played or 0,
            sessions = st.sessions or 0,
          })
        end
      end
    end
  end

  -- запасной список, если папки пустые
  if #res == 0 then
    res = {
      {id="snake",    title="Snake",    path="/home/games/snake",    created=os.time()*1000-86400*11*1000, played=0,    sessions=0},
      {id="tetris",   title="Tetris",   path="/home/games/tetris",   created=os.time()*1000-86400*18*1000, played=134,  sessions=4},
      {id="2048",     title="2048",     path="/home/games/2048",     created=os.time()*1000-86400*21*1000, played=47,   sessions=2},
      {id="pong",     title="Pong",     path="/home/games/pong",     created=os.time()*1000-86400*60*1000, played=65,   sessions=3},
      {id="mines",    title="Mines",    path="/home/games/mines",    created=os.time()*1000-86400*80*1000, played=nil,  sessions=0},
      {id="breakout", title="Breakout", path="/home/games/breakout", created=os.time()*1000-86400*95*1000, played=212,  sessions=6},
    }
  end

  -- сортировка по текущему режиму
  local mode = state.sortMode
  table.sort(res, function(a,b)
    if mode=="date" then
      return (a.created or 0) > (b.created or 0)
    else
      return unicode.lower(a.title) < unicode.lower(b.title)
    end
  end)
  state.games = res
  if #state.games == 0 then state.selection = nil end
  if state.page > math.max(1, math.ceil(#res/state.perPage)) then state.page = 1 end
end

-- ===== запуск игры ===========================================================
local function runGame(g)
  if not g then return end
  local ok, boot = pcall(require, "gamesboot")
  if ok and type(boot)=="table" then
    rcui.log("Запуск: "..g.title)
    local ok2, err = pcall(function()
      if boot.run then
        boot.run(g.id, g.path)
      elseif boot.start then
        boot.start(g.id, g.path)
      else
        error("gamesboot: нет функции run/start")
      end
    end)
    if not ok2 then rcui.log("Ошибка запуска: "..tostring(err)) end
  else
    rcui.log("gamesboot не найден, путь: "..tostring(g.path))
  end
  -- обновим статистику
  stats[g.id] = stats[g.id] or {}
  stats[g.id].sessions = (stats[g.id].sessions or 0) + 1
  saveStats(stats)
end

-- ===== действия UI ===========================================================
local function selectByIndex(idx)
  local g = state.games[idx]
  if g then state.selection = idx end
end

local function selectedGame() return state.games[state.selection or 0] end

local function nextPage(delta)
  local pages = math.max(1, math.ceil(#state.games/state.perPage))
  state.page = math.max(1, math.min(pages, state.page + delta))
end

local function toggleSort()
  state.sortMode = (state.sortMode=="az") and "date" or "az"
  scanGames()
end

-- ============================================================================

scanGames()

local W, H = 160, 50
local gridX, gridY = 4, 6
local cardW, cardH = 40, 14
local gapX, gapY   = 6, 5

local rightX = gridX + 3*(cardW+gapX) + 4
local rightW = W - rightX - 3

local bottomY = H - 5
local btnH = 3
local btnGap = 2
local btnW = math.floor((W - 6 - btnGap*5)/5)

-- рисуем подчёркнутый заголовок по центру
local function drawHeader(ui, text)
  local x = math.floor(W/2 - unicode.len(text)/2)
  ui.text(x, 2, text, rcui.colors().accent)
end

-- рамка выделения карточки
local function drawSelectionFrame(ui, x,y,w,h)
  local col = rcui.colors().accent
  ui.lineH(x, y, w, col)
  ui.lineH(x, y+h-1, w, col)
  ui.lineV(x, y, h, col)
  ui.lineV(x+w-1, y, h, col)
end

local function gameLines(g)
  return { "Создано:  "..fmtDate(g.created), "Сыграно:  "..fmtPlayed(g.played) }
end

-- основной кадр
local function render(ui)
  drawHeader(ui, "HauseMasters")

  -- страничный вывод карточек
  local from = (state.page-1)*state.perPage + 1
  local to   = math.min(#state.games, from + state.perPage - 1)
  local idx  = from
  local frameOfSelected = nil

  for row=0,1 do
    for col=0,2 do
      if idx > to then break end
      local g = state.games[idx]
      local x = gridX + col*(cardW+gapX)
      local y = gridY + row*(cardH+gapY)
      rcui.gameCard(x, y, cardW, cardH, {
        title   = g.title,
        lines   = gameLines(g),
        button  = "Играть",
        id      = idx,
        onClick = function() state.selection = idx; runGame(g) end
      })
      if idx == state.selection then
        frameOfSelected = {x=x,y=y,w=cardW,h=cardH}
      end
      -- клик по «тело карточки» для выбора без запуска
      rcui.colors() -- no-op, чтобы не ругался линтер
      rcui.panelBox(0,0,0,0) -- no-op; вызов ради инлайна (без эффекта)
      -- регистрация клика выбора
      local function choose() selectByIndex(idx) end
      -- прямоугольник всей карточки (минус кнопка) — зарегистрируем клик
      -- имитируем область: верх  y .. y+cardH-4
      local addClick = ui.addClick
      addClick(x, y, x+cardW-1, y+cardH-4, function() choose() end, "select"..idx)

      idx = idx + 1
    end
  end

  if frameOfSelected then
    drawSelectionFrame(ui, frameOfSelected.x, frameOfSelected.y, frameOfSelected.w, frameOfSelected.h)
  end

  -- правая колонка: информация по выбранной игре
  rcui.panelBox(rightX, 5, rightW, 12, "Информация")
  local gsel = selectedGame()
  if gsel then
    ui.text(rightX+2, 7,  "Игра:", rcui.colors().sub)
    ui.text(rightX+9, 7,  gsel.title)
    ui.text(rightX+2, 9,  "Создано:", rcui.colors().sub)
    ui.text(rightX+12,9,  fmtDate(gsel.created))
    ui.text(rightX+2, 11, "Сыграно:", rcui.colors().sub)
    ui.text(rightX+12,11, fmtPlayed(gsel.played))
    ui.text(rightX+2, 13, "Сессии:", rcui.colors().sub)
    ui.text(rightX+12,13, tostring(gsel.sessions or 0))
  else
    ui.text(rightX+2, 7, "Выбери игру слева, чтобы увидеть детали", rcui.colors().accent)
  end

  rcui.drawMetricsPanel(rightX, 19, rightW, 4)
  rcui.drawLogPanel(rightX, 24, rightW, 10)

  -- нижние кнопки
  local x0 = 3
  rcui.button(x0, bottomY, btnW, btnH, "Обновить", "orange", function()
    scanGames()
    rcui.log("Список игр обновлён")
  end)

  rcui.button(x0+(btnW+btnGap), bottomY, btnW, btnH, "Сорт: "..(state.sortMode=="az" and "A→Z" or "Новые"), "gray", function()
    toggleSort()
    rcui.log("Сортировка: "..(state.sortMode=="az" and "A→Z" or "по дате"))
  end)

  rcui.button(x0+2*(btnW+btnGap), bottomY, btnW, btnH, "⟨ Стр", "gray", function() nextPage(-1) end)
  rcui.button(x0+3*(btnW+btnGap), bottomY, btnW, btnH, "Стр ⟩", "gray", function() nextPage(1) end)

  rcui.button(x0+4*(btnW+btnGap), bottomY, btnW, btnH, "Выход", "red", function() rcui.stop() end)

  -- индикатор страницы
  local pages = math.max(1, math.ceil(#state.games/state.perPage))
  local pageStr = string.format("Страница %d / %d", state.page, pages)
  ui.text( math.floor(W/2 - unicode.len(pageStr)/2), bottomY-1, pageStr, rcui.colors().sub)
end

rcui.run(render)

-- финальная очистка
local buffer = require("doubleBuffering")
buffer.clear(0x000000); buffer.drawChanges(); require("term").clear()

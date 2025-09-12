-- /home/hausegames.lua — Меню игр «HauseGames»
local fs        = require("filesystem")
local unicode   = require("unicode")
local rcui      = require("rcui")
local buffer    = require("doubleBuffering")
local serial    = require("serialization")

-- ---------- ИНИЦ ----------
rcui.init{
  w = 160, h = 50,
  theme  = "dark",
  bgDark = "/home/images/reactorGUI.pic",
  bgLight= "/home/images/reactorGUI_white.pic",
}
local C = rcui.colors()
local W, H = 160, 50

-- ---------- УТИЛЫ ----------
local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end

-- округлённый прямоугольник (радиус 1 символ)
local function roundedRect(x,y,w,h, col, bg)
  buffer.drawRectangle(x,y,w,h, col, 0, " ")
  bg = bg or C().bg
  -- «срезаем» 4 угла
  buffer.drawRectangle(x,       y,        1,1, bg,0," ")
  buffer.drawRectangle(x+w-1,   y,        1,1, bg,0," ")
  buffer.drawRectangle(x,       y+h-1,    1,1, bg,0," ")
  buffer.drawRectangle(x+w-1,   y+h-1,    1,1, bg,0," ")
end

local function shadowRoundedRect(x,y,w,h, body, shadow)
  buffer.drawRectangle(x+2,y+2,w,h, shadow or C().shadow, 0, " ")
  roundedRect(x,y,w,h, body or C().bgPane, C().bg)
end

local function centerX(x,w,str)
  return x + math.max(0, math.floor((w - unicode.len(str or ""))/2))
end

local function drawTitle()
  -- перекрываем жёлтую надпись на фоне и рисуем свою
  buffer.drawRectangle(4, 2, W-8, 3, 0x5A5A5A, 0, " ")
  local title = "HauseGames"
  buffer.drawText(centerX(4, W-8, title), 3, 0xFFD166, title) -- тёплый жёлтый
  -- маленькая голубая подпись как «версия/подзаголовок»
  local sub = "HauseMasters"
  buffer.drawText(centerX(4, W-8, sub), 4, C().accent, sub)
end

local function fmtPlayed(sec)
  sec = tonumber(sec or 0) or 0
  local m = math.floor(sec/60)
  local s = math.floor(sec%60)
  return string.format("%02d:%02d", m, s)
end

-- ---------- ЧТЕНИЕ ИГР ИЗ JSON ----------
local GAMES_DIR = "/home/games"

local function readFile(path)
  local f = io.open(path,"rb"); if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end

-- очень простой парсер массива объектов с полями name, created, played_seconds
local function parseGamesJSON(s)
  local res = {}
  -- сначала попытка через доступную json-библиотеку, если такая есть
  local ok, json = pcall(require, "json")
  if ok and json and json.decode then
    local t = json.decode(s)
    if type(t)=="table" then
      for _,v in ipairs(t) do
        table.insert(res, {
          title   = v.name or "Game",
          created = v.created or "--",
          played  = fmtPlayed(v.played_seconds or 0),
        })
      end
      return res
    end
  end
  -- fallback: извлекаем объекты регуляркой (для твоего формата достаточно)
  for name, created, played in s:gmatch('{%s*"name"%s*:%s*"([^"]+)"%s*,%s*"created"%s*:%s*"([^"]+)"%s*,%s*"played_seconds"%s*:%s*(%d+)%s*}') do
    table.insert(res, { title=name, created=created, played=fmtPlayed(played) })
  end
  return res
end

local function loadGames()
  local list = {}

  if fs.exists(GAMES_DIR) and fs.isDirectory(GAMES_DIR) then
    local target = fs.concat(GAMES_DIR, "games.json")
    if not fs.exists(target) then
      -- берём первый .json в папке, если games.json нет
      for f in fs.list(GAMES_DIR) do
        if f:match("%.json$") then target = fs.concat(GAMES_DIR, f); break end
      end
    end
    if target and fs.exists(target) then
      local s = readFile(target)
      if s then
        local parsed = parseGamesJSON(s)
        for _,g in ipairs(parsed) do table.insert(list, g) end
      end
    end
  end

  -- если ничего не нашли — вставим пример (на всякий)
  if #list == 0 then
    list = {
      { title="Snake",    created="2025-08-31", played=fmtPlayed(0)    },
      { title="Tetris",   created="2025-08-25", played=fmtPlayed(8040) },
      { title="2048",     created="2025-08-12", played=fmtPlayed(2820) },
      { title="Pong",     created="2025-07-08", played=fmtPlayed(3900) },
      { title="Mines",    created="2025-06-21", played=fmtPlayed(0)    },
      { title="Breakout", created="2025-06-01", played=fmtPlayed(12780)},
    }
  end

  -- максимум 6 (3×2), без пагинации
  local trimmed = {}
  for i=1, math.min(6, #list) do trimmed[i] = list[i] end
  return trimmed
end

local games = loadGames()
local selected = 1

-- ---------- КАРТОЧКА ИГРЫ (rounded) ----------
local function drawGameCard(x,y,w,h,g, onPlay, id)
  shadowRoundedRect(x,y,w,h, C().bgPane, C().shadow)

  -- левый цветной «градиент»
  local barX = x+2
  for i=0,h-6 do
    local t = i / math.max(1,h-6)
    local r = clamp(0x20 + math.floor(0x40*t), 0, 255)
    local col = (0x00 << 16) + (r << 8) + 0xFF -- бирюзово-голубой
    buffer.drawRectangle(barX, y+3+i, 2, 1, col, 0, " ")
  end

  -- текст: только имя, дата, сыграно
  buffer.drawText(x+6, y+2, C().text, g.title or "Game")
  buffer.drawText(x+6, y+4, C().sub,  "Создано:  "..(g.created or "--"))
  buffer.drawText(x+6, y+6, C().sub,  "Сыграно:  "..(g.played or "--:--"))

  -- кнопка «Играть» (rounded)
  local btnW, btnH = w-14, 4
  local bx = x + math.floor((w - btnW)/2)
  local by = y + h - btnH - 2
  shadowRoundedRect(bx, by, btnW, btnH, C().green, C().shadow)
  buffer.drawText(centerX(bx, btnW, "Играть"), by + math.floor(btnH/2), 0x000000, "Играть")

  -- клики
  rcui.colors() -- no-op
  rcui.panelBox(0,0,0,0) -- no-op для луа-линтера
  rcui.run -- dummy keep
  local function inRect(px,py, rx,ry,rw,rh) return px>=rx and px<=rx+rw-1 and py>=ry and py<=ry+rh-1 end
  -- регистрируем клик на кнопку
  rcui.colors -- noop
  local addClick = function(x1,y1,x2,y2,cb) table.insert(debug, x1 or 0); end -- будет переопределено ниже через ui.addClick
end

-- Перерисовщик кнопок снизу (2 ряда, rounded)
local function drawBottomButtons(ui, actions)
  -- 2 ряда по 3 кнопки
  local rows, cols = 2, 3
  local marginX, marginY = 4, 1
  local areaW = W - 2*marginX
  local areaH = 2*4 + marginY + 2         -- высота области под две полоски кнопок
  local cellW = math.floor((areaW - (cols-1)*2)/cols)
  local cellH = 4
  local startY = H - areaH

  local i = 1
  for r=1,rows do
    for c=1,cols do
      if i > #actions then break end
      local a = actions[i]
      local x = marginX + (c-1)*(cellW+2)
      local y = startY + (r-1)*(cellH+marginY)
      shadowRoundedRect(x,y,cellW,cellH, a.color, C().shadow)
      buffer.drawText(centerX(x,cellW,a.label), y+2, 0x000000, a.label)
      ui.addClick(x,y,x+cellW-1,y+cellH-1, function() a.onClick() end, "btn"..i)
      i = i + 1
    end
  end
end

-- ---------- ОСНОВНАЯ ОТРИСОВКА ----------
local gridX, gridY = 4, 7
local cardW, cardH = 44, 15
local gapX, gapY   = 6, 5

-- правая колонка с нормальным отступом
local rightMargin = 4
local rightW = 42
local rightX = W - rightW - rightMargin

local function render(ui)
  drawTitle()

  -- 3×2 карточки
  local idx = 1
  local selFrame = nil
  for row=0,1 do
    for col=0,2 do
      if not games[idx] then break end
      local x = gridX + col*(cardW+gapX)
      local y = gridY + row*(cardH+gapY)

      -- карточка
      shadowRoundedRect(x,y,cardW,cardH, C().bgPane, C().shadow)

      -- левый бар
      local barX = x+2
      for i=0,cardH-6 do
        local t = i / math.max(1,cardH-6)
        local col = 0x138CFF + math.floor(t*0x004080)
        buffer.drawRectangle(barX, y+3+i, 2, 1, clamp(col,0,0xFFFFFF), 0, " ")
      end

      -- текст
      local g = games[idx]
      buffer.drawText(x+6, y+2, C().text, g.title)
      buffer.drawText(x+6, y+4, C().sub,  "Создано:  "..g.created)
      buffer.drawText(x+6, y+6, C().sub,  "Сыграно:  "..g.played)

      -- кнопка «Играть»
      local btnW, btnH = cardW-14, 4
      local bx = x + math.floor((cardW - btnW)/2)
      local by = y + cardH - btnH - 2
      shadowRoundedRect(bx, by, btnW, btnH, C().green, C().shadow)
      buffer.drawText(centerX(bx, btnW, "Играть"), by+2, 0x000000, "Играть")

      -- клики: по карточке — выбрать; по кнопке — запуск
      ui.addClick(x, y, x+cardW-1, by-1, function() selected = idx end, "select"..idx)
      ui.addClick(bx, by, bx+btnW-1, by+btnH-1, function()
        selected = idx
        rcui.log("Запуск: "..g.title)
        -- здесь можешь дернуть gamesboot.run(...)
      end, "play"..idx)

      if idx == selected then
        -- подчёркнутая рамка выбора
        ui.lineH(x, y, cardW, C().accent)
        ui.lineH(x, y+cardH-1, cardW, C().accent)
        ui.lineV(x, y, cardH, C().accent)
        ui.lineV(x+cardW-1, y, cardH, C().accent)
      end

      idx = idx + 1
    end
  end

  -- правая колонка: панели БЕЗ скругления
  rcui.panelBox(rightX, 6, rightW, 8, "Информация")
  if games[selected] then
    local g = games[selected]
    ui.text(rightX+2, 8,  "Игра:", C().sub);      ui.text(rightX+9,  8,  g.title)
    ui.text(rightX+2, 10, "Создано:", C().sub);   ui.text(rightX+12, 10, g.created)
    ui.text(rightX+2, 12, "Сыграно:", C().sub);   ui.text(rightX+12, 12, g.played)
  else
    ui.text(rightX+2, 8, "Выбери игру слева, чтобы увидеть детали", C().accent)
  end

  rcui.drawMetricsPanel(rightX, 16, rightW, 4)
  rcui.drawLogPanel(rightX, 21, rightW, 12)

  -- нижние кнопки: 2 ряда × 3
  local actions = {
    { label="Обновить",        color=0xFFB84D, onClick=function()
        games = loadGames(); rcui.log("Список игр обновлён")
      end },
    { label="Сорт A→Z / Новые", color=C().pane, onClick=function()
        -- простая смена порядка: либо по названию, либо по дате-строке
        local byDate = false
        for i=1,#games-1 do
          if games[i].created < games[i+1].created then byDate=true break end
        end
        if byDate then
          table.sort(games, function(a,b) return unicode.lower(a.title) < unicode.lower(b.title) end)
          rcui.log("Сортировка: A→Z")
        else
          table.sort(games, function(a,b) return a.created > b.created end)
          rcui.log("Сортировка: по дате")
        end
      end },
    { label="Тема",            color=C().accent, onClick=function()
        -- просто переинициализируем другую тему, фоны сохраняем
        local newTheme = (rcui.colors()==C and "light") or "light" -- no-op для линтера
        local cur = (C()==nil and "dark") or "dark"
        rcui.init{ w=W, h=H, theme = (C().bg==0xCFCFCF) and "dark" or "light",
                   bgDark="/home/images/reactorGUI.pic", bgLight="/home/images/reactorGUI_white.pic" }
      end },
    { label="Играть выбранную", color=0x33CC66, onClick=function()
        if games[selected] then rcui.log("Запуск: "..games[selected].title) end
      end },
    { label="Удалить из списка", color=0xE85C5C, onClick=function()
        if games[selected] then
          rcui.log("Игра скрыта: "..games[selected].title)
          table.remove(games, selected); selected = math.max(1, math.min(selected, #games))
        end
      end },
    { label="Выход",           color=0xFF8A65, onClick=function() rcui.stop() end },
  }
  drawBottomButtons(ui, actions)
end

-- ---------- ЗАПУСК ----------
rcui.run(render)

-- аккуратно очистим
buffer.clear(0x000000); buffer.drawChanges(); require("term").clear()

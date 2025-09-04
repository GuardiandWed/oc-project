-- /home/hausegames.lua
-- HauseGames: стартовый лаунчер игр под OpenComputers

local fs         = require("filesystem")
local event      = require("event")
local shell      = require("shell")

local gui        = require("ugui")         -- наш лёгкий UI слой (поверх ugui_core)
local core       = require("ugui_core")
local gamesboot  = require("gamesboot")

-- ---------- ТЕМА (можно крутить в одном месте)
local theme = {
  bg        = 0x1b1b1b,  -- основной фон
  fg        = 0xE6E6E6,  -- основной текст
  cardBg    = 0x242424,  -- фон карточек
  cardFg    = 0xEDEDED,
  border    = 0x3D8DFF,  -- акцентная рамка
  accent    = 0x00D1B2,  -- акцент (кнопки)
  danger    = 0xFF5468,  -- “выход”
  subtle    = 0x888888
}

-- ---------- ИНИТ ЭКРАН/БУФЕР
core.init_screen(theme.bg, theme.fg)
local W, H = core.size()

-- ---------- ЛОГО / ШАПКА
local function draw_header()
  local title = " HAUSEGAMES "
  local x = math.floor((W - #title) / 2)
  gui.label(x, 2, title, theme.fg)
end

-- ---------- КАРТОЧКИ ИГР (пока пустые, с плейсхолдерами)
-- сетка 3 x 2 как в примере (можно менять rows/cols)
local rows, cols = 2, 3
local padX, padY = 6, 4
local cardW, cardH = 26, 10

-- левый верхний угол области карточек
local gridX = 6
local gridY = 6

local cards = {}

local function make_card(x, y, w, h, title, sub1, sub2)
  core.fill(x, y, w, h, " ", theme.cardBg, theme.cardFg)
  core.border(x, y, w, h, theme.border)

  gui.label(x+2, y+1, title or "Игра", theme.cardFg)
  gui.label(x+2, y+3, sub1 or "Создано: --", theme.subtle)
  gui.label(x+2, y+4, sub2 or "Сыграно: --", theme.subtle)

  -- заглушка кнопки “Запустить” (без логики запуска)
  local bx, by, bw = x+2, y+h-2, w-4
  core.button(bx, by, bw, 1, " Запустить ", theme.accent, theme.cardBg, function()
    -- позже подставим gamesboot.run(game)
  end)

  table.insert(cards, {x=x,y=y,w=w,h=h})
end

local function draw_cards()
  cards = {}
  local gx, gy = gridX, gridY
  local idx = 1

  -- получим список игр (сейчас — моковые данные от gamesboot)
  local list = gamesboot.list_games()

  for r=1, rows do
    for c=1, cols do
      local x = gx + (c-1) * (cardW + padX)
      local y = gy + (r-1) * (cardH + padY)

      local item = list[idx]
      if item then
        local t  = item.name or ("Игра "..idx)
        local d1 = "Создано: " .. (item.created or "--")
        local d2 = "Сыграно: " .. (item.played_h or "--")
        make_card(x, y, cardW, cardH, t, d1, d2)
      else
        make_card(x, y, cardW, cardH, "Пусто", "Добавь игру", "--")
      end
      idx = idx + 1
    end
  end
end

-- ---------- ПАНЕЛЬ НИЗА (кнопки)
local function draw_footer()
  local y = H - 3

  -- Рестарт
  core.button(4, y, 20, 1, " Рестарт программы ", theme.accent, theme.bg, function()
    -- мягкая перерисовка
    core.clear(theme.bg, theme.fg)
    draw_header()
    draw_cards()
    draw_footer()
    core.present()
  end)

  -- Выход
  core.button(28, y, 18, 1, " Выход из программы ", theme.danger, theme.bg, function()
    core.shutdown()
  end)

  -- маленький статус справа
  local info = "W:"..W.." H:"..H
  gui.label(W-#info-2, y, info, theme.subtle)
end

-- ---------- РЕНДЕР ПОЛНОЙ СЦЕНЫ
local function render()
  core.clear(theme.bg, theme.fg)
  draw_header()
  draw_cards()
  draw_footer()
  core.present()
end

-- ---------- MAIN LOOP
render()

while true do
  local ev = {event.pull(0.2)}
  if ev[1] == "touch" then
    local _, _, tx, ty = table.unpack(ev)
    core.dispatch_click(tx, ty)  -- проверяем попадание по всем кнопкам
  elseif ev[1] == "interrupted" or ev[1] == "key_down" and ev[4] == 46 then
    -- Ctrl-C или клавиша 'C' с Ctrl (scancode 46) — выходим
    core.shutdown()
  end
end

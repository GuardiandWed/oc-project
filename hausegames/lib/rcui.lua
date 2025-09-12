-- /lib/rcui.lua — минимальный UI-слой "как у друга": doubleBuffering + image + карточки/кнопки/панели
-- зависит от: doubleBuffering.lua, image.lua (+ модуль формата .pic), unicode, event, computer

local buffer    = require("doubleBuffering")
local image     = require("image")
local unicode   = require("unicode")
local event     = require("event")
local computer  = require("computer")

-- попытка автоподключить модуль формата .pic (если у тебя плагинная image.lua)
pcall(function()
  if image.loadFormatModule then
    image.loadFormatModule("/lib/FormatModules/PIC.lua", ".pic")
  end
end)

local M = {}

-- ======= STATE =======
local S = {
  W = 160, H = 50,
  theme  = "dark",   -- "dark" | "light"
  bgDark = nil,      -- пути к .pic
  bgLight= nil,
  bgPic  = nil,      -- кэш загруженной фон. картинки
  colors = {},
  clickAreas = {},   -- { {x1,y1,x2,y2, cb, id}, ... }
  log = { "HauseGames UI запущен" },
  running = false,
  fps = 0, frames = 0, lastFPS = computer.uptime(),
  lastDraw = 0,
}

-- ======= THEMES =======
local THEMES = {
  dark = {
    bg     = 0x3a3a3a, -- общий фон (как на примере — тёмно-серый)
    bgPane = 0x1f1f1f, -- тёмные карточки/плашки
    pane   = 0x232323, -- ещё один оттенок для рамок
    text   = 0xE6E6E6, -- основной текст
    sub    = 0xB0B0B0, -- подписи/вторичный
    accent = 0x29A8FF, -- голубой акцент (кнопки/линии)
    green  = 0x33CC66, -- «включить»
    red    = 0xE85C5C, -- «стоп/опасно»
    orange = 0xFFB84D,
    shadow = 0x101010, -- тень карточек
    line   = 0x1a1a1a, -- разделители
  },
  light = {
    bg     = 0xCFCFCF,
    bgPane = 0x2A2A2A,
    pane   = 0x2F2F2F,
    text   = 0xFFFFFF,
    sub    = 0xDDDDDD,
    accent = 0x29A8FF,
    green  = 0x33CC66,
    red    = 0xE85C5C,
    orange = 0xFFB84D,
    shadow = 0x202020,
    line   = 0xB0B0B0,
  }
}

-- ======= INTERNAL =======
local function C() return S.colors end

local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end

local function drawShadowRect(x,y,w,h, body, shadow)
  buffer.drawRectangle(x+1,y+1,w,h, shadow or C().shadow, 0, " ")
  buffer.drawRectangle(x,y,w,h, body or C().bgPane, 0, " ")
end

local function drawFrame(x,y,w,h, fill, border)
  buffer.drawRectangle(x,y,w,h, fill or C().bgPane, 0, " ")
  -- псевдо-рамка тонкой линией
  local b = border or C().line
  buffer.drawRectangle(x,y,w,1,b,0," ")
  buffer.drawRectangle(x,y,1,h,b,0," ")
  buffer.drawRectangle(x,y+h-1,w,1,b,0," ")
  buffer.drawRectangle(x+w-1,y,1,h,b,0," ")
end

local function centerX(x,w,str)
  return x + math.max(0, math.floor((w - unicode.len(str or ""))/2))
end

local function addClick(x1,y1,x2,y2, cb, id)
  table.insert(S.clickAreas, {x1=x1,y1=y1,x2=x2,y2=y2, cb=cb, id=id})
end

local function clearClicks()
  S.clickAreas = {}
end

-- форматы чисел
local function fmtUptime(sec)
  local s = math.floor(sec%60)
  local m = math.floor(sec/60)%60
  local h = math.floor(sec/3600)
  return string.format("%02d:%02d:%02d", h,m,s)
end

local function fmtKiB(bytes)
  local kib = math.floor(bytes/1024)
  if kib < 1024 then return string.format("%d KiB", kib) end
  local mib = kib/1024
  if mib < 1024 then return string.format("%.1f MiB", mib) end
  local gib = mib/1024
  return string.format("%.1f GiB", gib)
end

-- ======= PUBLIC: basic =======
function M.colors() return C() end

function M.log(msg)
  table.insert(S.log, msg)
  if #S.log > 100 then table.remove(S.log,1) end
end

function M.setBackgrounds(darkPath, lightPath)
  S.bgDark, S.bgLight = darkPath, lightPath
  S.bgPic = nil
end

local function tryLoadBG()
  local path = (S.theme=="light") and S.bgLight or S.bgDark
  if path and not S.bgPic then
    local ok, pic = pcall(image.load, path)
    if ok and pic then S.bgPic = pic end
  end
end

local function drawBackground()
  if S.bgPic then
    buffer.drawImage(1,1,S.bgPic)
  else
    buffer.drawRectangle(1,1,S.W,S.H,C().bg,0," ")
  end
end

-- ======= PUBLIC: init/run =======
function M.init(opts)
  opts = opts or {}
  S.W  = opts.w or S.W
  S.H  = opts.h or S.H
  S.theme = (opts.theme == "light") and "light" or "dark"
  S.colors = THEMES[S.theme] or THEMES.dark
  buffer.setResolution(S.W, S.H)

  if opts.bgDark or opts.bgLight then
    M.setBackgrounds(opts.bgDark, opts.bgLight)
  end
  tryLoadBG()
end

function M.getMetrics()
  local used = computer.totalMemory() - computer.freeMemory()
  return {
    fps = S.fps,
    mem = used,
    uptime = computer.uptime()
  }
end

-- главный цикл. renderFn(canvasAPI) — функция кадра
function M.run(renderFn)
  if S.running then return end
  S.running = true
  while S.running do
    clearClicks()
    drawBackground()

    -- дать пользователю дорисовать кадр и зарегистрировать клики
    local api = {
      colors = M.colors,
      addClick = addClick,
      drawShadowRect = drawShadowRect,
      drawFrame = drawFrame,
      centerX = centerX,
      rect = function(x,y,w,h,col) buffer.drawRectangle(x,y,w,h,col or C().bgPane,0," ") end,
      text = function(x,y,str,col) buffer.drawText(x,y,col or C().text, str or "") end,
      lineH = function(x,y,w,col) buffer.drawRectangle(x,y,w,1,col or C().line,0," ") end,
      lineV = function(x,y,h,col) buffer.drawRectangle(x,y,1,h,col or C().line,0," ") end,
      -- элементы выше уровня
    }
    if renderFn then renderFn(api) end

    -- FPS
    S.frames = S.frames + 1
    local t = computer.uptime()
    if t - S.lastFPS >= 1 then
      S.fps = S.frames
      S.frames = 0
      S.lastFPS = t
    end

    buffer.drawChanges()
    -- события: клики
    local ev = { event.pull(0.05) }
    if ev[1] == "touch" then
      local _addr, x, y = ev[2], ev[3], ev[4]
      for _,a in ipairs(S.clickAreas) do
        if x>=a.x1 and x<=a.x2 and y>=a.y1 and y<=a.y2 then
          pcall(a.cb, a.id, x, y)
          break
        end
      end
    elseif ev[1] == "key_down" then
      local _,_,_,key = table.unpack(ev)
      if key == 0x11 then -- Q
        S.running = false
      end
    end
  end
end

function M.stop()
  S.running = false
end

-- ======= PUBLIC: widgets =======

-- заголовок панели
function M.panelBox(x,y,w,h,title)
  drawShadowRect(x,y,w,h,C().bgPane,C().shadow)
  if title and title~="" then
    buffer.drawText(x+2, y, C().accent, title)
    buffer.drawRectangle(x+1, y+1, w-2, 1, C().line, 0, " ")
  end
end

-- простая кнопка (цветные «капсулы»)
function M.button(x,y,w,h,label, style, onClick, id)
  local col = C().accent
  if style=="green" then col=C().green
  elseif style=="red" then col=C().red
  elseif style=="gray" then col=C().pane
  elseif style=="orange" then col=C().orange
  end
  drawShadowRect(x,y,w,h,col,C().shadow)
  buffer.drawText(centerX(x,w,label), y+math.floor(h/2), 0x000000, label or "")
  if onClick then
    addClick(x,y,x+w-1,y+h-1,onClick,id)
  end
end

-- «классическая» карточка как у друга: тёмная плитка + индикатор слева + кнопка снизу
function M.gameCard(x,y,w,h, opt)
  opt = opt or {}
  drawShadowRect(x,y,w,h,C().bgPane,C().shadow)
  -- левый индикатор (градиент голубой)
  local barX = x+2
  for i=0,h-4 do
    local t = i/(h-4)
    local col = 0x1A6DFF + math.floor(t*0x0080AA)
    buffer.drawRectangle(barX, y+2+i, 2, 1, clamp(col,0,0xFFFFFF), 0, " ")
  end

  -- заголовок
  buffer.drawText(x+6, y+2, C().text, opt.title or "Game")
  -- метаданные
  if opt.lines then
    for i,ln in ipairs(opt.lines) do
      buffer.drawText(x+6, y+3+i, C().sub, ln)
    end
  end

  -- кнопка
  local btnW, btnH = w-12, 3
  local bx = x + math.floor((w - btnW)/2)
  local by = y + h - btnH - 2
  M.button(bx, by, btnW, btnH, opt.button or "Запустить", "green", opt.onClick, opt.id)

  -- маленькие «скобки» внизу для стиля
  buffer.drawText(x+4, y+h-1, C().accent, "▝")
  buffer.drawText(x+w-5, y+h-1, C().accent, "▘")
end

-- мелкая подпись справа (панель метрик-логов)
function M.kv(x,y,k,v)
  buffer.drawText(x,y, C().sub, k)
  buffer.drawText(x+unicode.len(k)+1, y, C().text, v)
end

-- рисовалка статусов в правой колонке
function M.drawMetricsPanel(x,y,w,h)
  M.panelBox(x,y,w,h,"Системные метрики")
  local m = M.getMetrics()
  M.kv(x+2,y+2,"FPS:", tostring(m.fps))
  M.kv(x+12,y+2,"Память:", fmtKiB(m.mem))
  M.kv(x+28,y+2,"Uptime:", fmtUptime(m.uptime))
end

function M.drawLogPanel(x,y,w,h)
  M.panelBox(x,y,w,h,"Журнал")
  local maxLines = h-3
  local start = math.max(1, #S.log - maxLines + 1)
  local yy = y+2
  for i=start,#S.log do
    buffer.drawText(x+2, yy, C().text, S.log[i])
    yy = yy + 1
  end
end

return M

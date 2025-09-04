-- /home/hausegames.lua — подгонка размеров/отступов

local event = require("event")
local core  = require("ugui_core")
local gui   = require("ugui")
local boot  = require("gamesboot")

core.init_screen(core.theme.bg, core.theme.text)
local W,H = core.size()

-- сетка 3×2
local rows, cols    = 2,3
local cardW, cardH  = 26,11
local padX, padY    = 10,8

-- поле игр
local gridX, gridY  = 3,6   -- чуть выше заголовка уменьшенного
local gridW         = cols*cardW + (cols-1)*padX + 10
local gridH         = rows*cardH + (rows-1)*padY + 10

-- правая колонка
local sidebarX      = gridX + gridW + 4
local sidebarW      = math.max(36, W - sidebarX - 3)
local sideTop       = gridY
local sideGap       = 4

local function header() gui.drawMain() end
local function draw_grid_bg() gui.bigGrid(gridX-2, gridY-2, gridW, gridH) end

local function draw_card(x,y,w,h, g)
  gui.card(x,y,w,h)
  local name    = g and g.name or "Пусто"
  local created = g and g.created or "--"
  local played  = g and g.played_h or "--"
  gui.text(x+3, y+2, "&f"..name)
  gui.text(x+3, y+4, "&7Создано: &f"..created)
  gui.text(x+3, y+5, "&7Сыграно: &f"..played)
  gui.button(x+4, y+h-4, w-8, 3, "Запустить", {
    bg = core.theme.primary, fg = 0x000000,
    parentBg = core.theme.card,   -- важно для красивых скруглений кнопки
    radius   = 2,
    onClick  = function() require("gamesboot").run(name) end
  })
end

local function draw_grid()
  local list = boot.list_games()
  local idx = 1
  for r=1,rows do
    for c=1,cols do
      local x = gridX + (c-1)*(cardW+padX)
      local y = gridY + (r-1)*(cardH+padY)
      draw_card(x,y,cardW,cardH, list[idx]); idx = idx + 1
    end
  end
end

local function draw_sidebar()
  gui.drawFrame(sidebarX, sideTop, sidebarW, 14, "Информация")
  gui.text(sidebarX+2, sideTop+2, "&7Выбери игру слева, чтобы увидеть детали")

  local y = sideTop + 14 + sideGap
  gui.drawFrame(sidebarX, y, sidebarW, 6, "Системные метрики")
  gui.text(sidebarX+2, y+2, "&7FPS: &f--    &7Память: &f--    &7Uptime: &f--")

  y = y + 6 + sideGap
  gui.drawFrame(sidebarX, y, sidebarW, 8, "Журнал")
  gui.text(sidebarX+2, y+2, "&7Здесь позже будет лог запуска игр…")
end

local function restart_program()
  core.clear()
  local f,err = loadfile("/home/hausegames.lua")
  if not f then gui.text(2, H-1, "&cОшибка загрузки: &f"..tostring(err)); core.flush() else f() end
end

local function draw_footer()
  local y = H - 4
  gui.button(4,  y, 30, 3, "Рестарт программы", {
    bg = core.theme.primary, fg = 0x000000, parentBg = core.theme.bg, radius=2,
    onClick = restart_program
  })
  gui.button(38, y, 30, 3, "Выход из программы", {
    bg = core.theme.danger, fg = 0x000000, parentBg = core.theme.bg, radius=2,
    onClick = function() if _G.__hg_bot then pcall(_G.__hg_bot.stop, _G.__hg_bot) end; core.shutdown() end
  })
end

local function render()
  core.clear(core.theme.bg)
  header()
  draw_grid_bg()
  draw_grid()
  draw_sidebar()
  draw_footer()
  core.flush()
end

render()

local Chat = require("chatcmd")
local bot = Chat.new{ prefix="@", name="Оператор", admins={"HauseMasters"} }
bot:start()
_G.__hg_bot = bot

while true do
  local ev = {event.pull()}
  if ev[1] == "touch" then
    local _,_,x,y = table.unpack(ev)
    core.dispatch_click(x,y)
  elseif ev[1] == "interrupted" then
    core.shutdown()
  end
end

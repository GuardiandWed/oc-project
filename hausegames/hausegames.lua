-- /home/hausegames.lua

local function die(msg) io.stderr:write("[HauseGames] "..tostring(msg).."\n"); os.exit(1) end
local ok,e = pcall(require,"event");         if not ok then die(e) end; local event = e
ok,e = pcall(require,"ugui_core");           if not ok then die(e) end; local core  = e
ok,e = pcall(require,"ugui");                if not ok then die(e) end; local gui   = e
ok,e = pcall(require,"gamesboot");           if not ok then die(e) end; local boot  = e

core.init_screen(core.theme.bg, core.theme.text)
local W,H = core.size()

local rows, cols  = 2,3
local cardW, cardH = 26,10
local padX, padY  = 6,4
local gridX, gridY = 4,6

local sidebarX = gridX + cols*(cardW+padX) + 6
local sidebarW = math.max(28, W - sidebarX - 4)
local sideTop, sideGap = gridY, 2

local function header()
  gui.drawMain("&e HAUSE&fGAMES  &7— выбери игру", "9")
end

local function draw_card(x,y,w,h, game)
  gui.card(x,y,w,h)
  local name    = game and game.name or "Пусто"
  local created = game and game.created or "--"
  local played  = game and game.played_h or "--"
  gui.text(x+2, y+1, "&f"..name)
  gui.text(x+2, y+3, "&7Создано: &f"..created)
  gui.text(x+2, y+4, "&7Сыграно: &f"..played)
  gui.button(x+2, y+h-2, w-4, 1, " Запустить ", {
    bg = core.theme.primary, fg = 0x000000,
    onClick = function() boot.run(name) end
  })
end

local function draw_grid()
  local list = boot.list_games()
  local idx = 1
  for r=1,rows do
    for c=1,cols do
      local x = gridX + (c-1)*(cardW+padX)
      local y = gridY + (r-1)*(cardH+padY)
      draw_card(x,y,cardW,cardH, list[idx])
      idx = idx + 1
    end
  end
end

local function draw_sidebar()
  gui.drawFrame(sidebarX, sideTop, sidebarW, 14, "Информация", "9")
  gui.text(sidebarX+2, sideTop+2, "&7Выбери игру слева, чтобы увидеть детали")

  local y = sideTop + 14 + sideGap
  gui.drawFrame(sidebarX, y, sidebarW, 5, "Системные метрики", "9")
  gui.text(sidebarX+2, y+2, "&7FPS: &f--   &7Память: &f--   &7Uptime: &f--")

  y = y + 5 + sideGap
  gui.drawFrame(sidebarX, y, sidebarW, 7, "Журнал", "9")
  gui.text(sidebarX+2, y+2, "&7Здесь позже будет лог запуска игр…")
end

local function draw_footer()
  local y = H - 3
  gui.button(4, y, 22, 1, " Рестарт программы ", {
    bg = core.theme.primary, fg = 0x000000,
    onClick = function()
      core.clear(); header(); draw_grid(); draw_sidebar(); draw_footer(); core.flush()
    end
  })
  gui.button(28, y, 20, 1, " Выход из программы ", {
    bg = core.theme.danger, fg = 0x000000,
    onClick = function() core.shutdown() end
  })
end

local function render()
  core.clear()
  header(); draw_grid(); draw_sidebar(); draw_footer()
  core.flush()
end

render()

while true do
  local ev = {event.pull()}
  if ev[1] == "touch" then
    local _,_,x,y = table.unpack(ev)
    core.dispatch_click(x,y)
  elseif ev[1] == "interrupted" then
    core.shutdown()
  end
end

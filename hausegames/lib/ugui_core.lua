-- /home/lib/ugui_core.lua
-- Минималистичное рендер-ядро для GUI на OpenComputers + удобные виджеты.

local component = require("component")
local gpu       = component.gpu

local core = {}

----------------------------------------------------------------
-- ТЕМА (современные цвета можно менять тут)
----------------------------------------------------------------
core.theme = {
  bg      = 0x161616, -- общий фон
  text    = 0xEAEAEA, -- основной текст
  primary = 0x00D1B2, -- мятно-бирюзовый акцент
  border  = 0x3D8DFF, -- неоново-синий для рамок
  card    = 0x222222, -- фон карточек
  muted   = 0x8A8A8A, -- приглушённый текст
  danger  = 0xFF5468, -- красный для выхода
}

----------------------------------------------------------------
-- Состояние
----------------------------------------------------------------
local W, H = 80, 25
local buttons = {} -- интерактивы

----------------------------------------------------------------
-- Экран / буфер
----------------------------------------------------------------
function core.init_screen(bg, fg)
  local maxW, maxH = gpu.maxResolution()
  gpu.setResolution(maxW, maxH)
  W, H = gpu.getResolution()
  gpu.setBackground(bg or core.theme.bg)
  gpu.setForeground(fg or core.theme.text)
  gpu.fill(1,1,W,H," ")
end

function core.size() return W, H end

function core.clear(bg, fg)
  gpu.setBackground(bg or core.theme.bg)
  gpu.setForeground(fg or core.theme.text)
  gpu.fill(1,1,W,H," ")
  buttons = {}
end

function core.flush()
  -- в прямом рендере ничего не делаем; совместимость с двойным буфером
end
core.present = core.flush

----------------------------------------------------------------
-- Примитивы
----------------------------------------------------------------
function core.text(x,y,str,fg)
  if fg then gpu.setForeground(fg) end
  gpu.set(x,y,str or "")
end

function core.rect(x,y,w,h,bg,fg,char)
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  for i=0,h-1 do
    gpu.fill(x, y+i, w, 1, char or " ")
  end
end

function core.frame(x,y,w,h,col)
  local prev = {gpu.getForeground()}
  gpu.setForeground(col or core.theme.border)
  if w < 2 or h < 2 then return end
  gpu.set(x, y,           "┌"..string.rep("─",w-2).."┐")
  gpu.set(x, y+h-1,       "└"..string.rep("─",w-2).."┘")
  for i=1,h-2 do
    gpu.set(x, y+i,       "│")
    gpu.set(x+w-1, y+i,   "│")
  end
  gpu.setForeground(table.unpack(prev))
end

function core.card(x,y,w,h,title)
  core.rect(x,y,w,h, core.theme.card, core.theme.text, " ")
  core.frame(x,y,w,h, core.theme.border)
  if title and title ~= "" then
    core.text(x+2, y, "["..title.."]", core.theme.text)
  end
end

function core.vbar(x,y,h,value,min,max,col,back)
  min, max = min or 0, max or 100
  value = math.max(min, math.min(max, value or min))
  local fillH = math.floor((value - min) / (max - min) * h + 0.5)
  core.rect(x, y, 2, h, back or 0x1A1A1A)
  core.rect(x, y+h-fillH, 2, fillH, col or core.theme.primary)
  core.frame(x, y, 2, h, core.theme.border)
end

function core.logpane(x,y,w,h,lines)
  core.card(x,y,w,h)
  if not lines then return end
  local maxLines = h-2
  local start = math.max(1, #lines - maxLines + 1)
  local cy = y+1
  for i=start,#lines do
    local s = tostring(lines[i])
    if #s > w-2 then s = s:sub(1, w-5).."..." end
    core.text(x+1, cy, s, core.theme.muted)
    cy = cy + 1
  end
end

----------------------------------------------------------------
-- Кнопки
----------------------------------------------------------------
local function within(mx,my,b)
  return mx>=b.x and mx<=b.x+b.w-1 and my>=b.y and my<=b.y+b.h-1
end

function core.button(x,y,w,h,label,bg,fg,onClick)
  core.rect(x,y,w,h, bg or core.theme.primary, fg or 0x000000, " ")
  core.frame(x,y,w,h, fg or 0x000000)
  if label and label~="" then
    local tx = x + math.floor((w - #label)/2)
    local ty = y + math.floor(h/2)
    core.text(tx, ty, label, fg or 0x000000)
  end
  local b = {x=x,y=y,w=w,h=h,onClick=onClick}
  table.insert(buttons, b)
  return b
end

function core.inBounds(ctrl, cx, cy)
  return ctrl and within(cx,cy,ctrl) or false
end

function core.dispatch_click(px,py)
  for _,b in ipairs(buttons) do
    if within(px,py,b) then
      if b.onClick then pcall(b.onClick) end
      return true
    end
  end
  return false
end

function core.shutdown()
  gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
  local w,h = gpu.getResolution()
  gpu.fill(1,1,w,h," ")
  os.exit()
end

return core

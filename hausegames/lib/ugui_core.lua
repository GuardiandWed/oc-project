-- /lib/ugui_core.lua  (v2 “reactor look”)

local gpu = require("component").gpu

local core = {}

-- палитра/тема
core.theme = {
  -- фоны
  bg       = 0x141518,   -- общий фон
  gridBg   = 0x1A1C20,   -- фон под сеткой карточек
  panelBg  = 0x191A1E,   -- фон правых панелей
  card     = 0x202226,   -- фон карточек
  -- цвета
  text     = 0xE7E7E7,
  muted    = 0x9AA0A6,
  border   = 0x5A78FF,   -- “фиолетово-синий” как в примере
  primary  = 0x19D7C5,   -- бирюзовые акценты
  danger   = 0xFF5468,
  ok       = 0x19D78F,
  -- тени/обводки
  shadow1  = 0x0D0E10,   -- дальняя тень
  shadow2  = 0x121316,   -- ближняя тень
  outline  = 0x0B0B0D,   -- контур кнопок
}

local W,H = 80,25
local buttons = {}

-- screen -------------------------------------------------------
function core.init_screen(bg, fg)
  local maxW,maxH = gpu.maxResolution()
  gpu.setResolution(maxW,maxH)
  W,H = gpu.getResolution()
  gpu.setBackground(bg or core.theme.bg)
  gpu.setForeground(fg or core.theme.text)
  gpu.fill(1,1,W,H," ")
end

function core.size() return W,H end
function core.clear(bg,fg)
  gpu.setBackground(bg or core.theme.bg)
  gpu.setForeground(fg or core.theme.text)
  gpu.fill(1,1,W,H," ")
  buttons = {}
end
function core.flush() end
core.present = core.flush

-- primitives ---------------------------------------------------
local function setfg(c) if c then gpu.setForeground(c) end end
local function setbg(c) if c then gpu.setBackground(c) end end

function core.text(x,y,s,fg) setfg(fg); gpu.set(x,y,s or "") end

function core.rect(x,y,w,h,bg,fg,char)
  setbg(bg); setfg(fg)
  for i=0,h-1 do gpu.fill(x, y+i, w, 1, char or " ") end
end

-- тонкая рамка
local function frame1(x,y,w,h,col)
  local prev = {gpu.getForeground()}
  gpu.setForeground(col or core.theme.border)
  if w>=2 and h>=2 then
    local tl,tr,bl,br = "╭","╮","╰","╯"
    gpu.set(x, y,         tl..string.rep("─",w-2)..tr)
    gpu.set(x, y+h-1,     bl..string.rep("─",w-2)..br)
    for i=1,h-2 do
      gpu.set(x,     y+i, "│")
      gpu.set(x+w-1, y+i, "│")
    end
  end
  gpu.setForeground(table.unpack(prev))
end

-- утолщённая рамка с “объёмом”
function core.frame(x,y,w,h,col)
  -- внешняя «светлая» обводка
  frame1(x, y, w, h, col or core.theme.border)
  -- внутренняя полутонкая псевдо-рамка создаёт ощущение толщины
  if w>4 and h>4 then frame1(x+1, y+1, w-2, h-2, 0x3C4FBF) end
end

-- карточка с двойной тенью
function core.card_shadow(x,y,w,h,bg,border,shadow,title)
  -- тени: дальняя и ближняя
  core.rect(x+2,y+2,w,h, core.theme.shadow1)
  core.rect(x+1,y+1,w,h, core.theme.shadow2)
  -- фон
  core.rect(x,y,w,h, bg or core.theme.card)
  -- рамка
  core.frame(x,y,w,h, border or core.theme.border)
  -- заголовок
  if title and title~="" then
    core.text(x+2,y,"["..title.."]", core.theme.text)
  end
end

function core.card(x,y,w,h,title)
  core.card_shadow(x,y,w,h, core.theme.card, core.theme.border, core.theme.shadow2, title)
end

-- вертикальная шкала (без изменений)
function core.vbar(x,y,h,value,min,max,col,back)
  min,max = min or 0, max or 100
  value   = math.max(min, math.min(max, value or min))
  local fillH = math.floor((value-min)/(max-min)*h + 0.5)
  core.rect(x, y, 2, h, back or 0x15171A)
  core.rect(x, y+h-fillH, 2, fillH, col or core.theme.primary)
  core.frame(x, y, 2, h, core.theme.border)
end

-- лог-панель
function core.logpane(x,y,w,h,lines)
  core.card_shadow(x,y,w,h, core.theme.panelBg, core.theme.border, core.theme.shadow2)
  if not lines then return end
  local maxLines = h-2
  local start = math.max(1, #lines - maxLines + 1)
  local cy = y+1
  for i=start,#lines do
    local s = tostring(lines[i]); if #s>w-2 then s=s:sub(1,w-5).."..." end
    core.text(x+1, cy, s, core.theme.muted); cy = cy + 1
  end
end

-- кнопки -------------------------------------------------------
local function inside(mx,my,b) return mx>=b.x and mx<=b.x+b.w-1 and my>=b.y and my<=b.y+b.h-1 end

-- крупная “скруглённая” кнопка с тенью (h>=3)
function core.button(x,y,w,h,label,bg,fg,onClick)
  h = math.max(3, h or 3)
  label = label or "OK"
  bg = bg or core.theme.primary
  fg = fg or 0x000000

  -- тень
  core.rect(x+2, y+1, w, h, core.theme.shadow2)

  -- тело
  core.rect(x, y, w, h, bg)

  -- лёгкое «скругление» сверху/снизу за счёт отступов
  if w>=4 then
    setbg(bg)
    gpu.fill(x,     y,     1, 1, " ")
    gpu.fill(x+w-1, y,     1, 1, " ")
    gpu.fill(x,     y+h-1, 1, 1, " ")
    gpu.fill(x+w-1, y+h-1, 1, 1, " ")
  end

  -- контур
  frame1(x, y, w, h, core.theme.outline)

  -- текст
  local tx = x + math.floor((w - #label)/2)
  local ty = y + math.floor(h/2)
  core.text(tx, ty, label, fg)

  local b = {x=x,y=y,w=w,h=h,onClick=onClick}; table.insert(buttons,b); return b
end

function core.inBounds(ctrl,x,y) return ctrl and inside(x,y,ctrl) or false end
function core.dispatch_click(x,y)
  for _,b in ipairs(buttons) do
    if inside(x,y,b) then if b.onClick then pcall(b.onClick) end; return true end
  end
  return false
end

function core.shutdown()
  gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
  local w,h = gpu.getResolution(); gpu.fill(1,1,w,h," "); os.exit()
end

return core

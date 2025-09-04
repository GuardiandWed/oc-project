-- /lib/ugui_core.lua  — стиль как на «реакторах»

local gpu = require("component").gpu
local core = {}

-- палитра, близкая к примеру
core.theme = {
  -- фоны
  bg       = 0x111214,   -- общий фон
  gridBg   = 0x2A2C31,   -- светлее под сеткой (как серое поле на примере)
  panelBg  = 0x26282D,   -- правые панели
  card     = 0x1B1D21,   -- сами карточки

  -- текст/цвета
  text     = 0xE3E6EA,
  muted    = 0xA0A6AE,
  border   = 0x6B72FF,   -- сине-фиолетовая рамка
  primary  = 0x12D4C6,   -- бирюзовые кнопки
  danger   = 0xFF6D86,   -- розово-красные кнопки
  ok       = 0x22D07E,

  -- тени/контуры
  shadow1  = 0x0A0B0D,
  shadow2  = 0x14161A,
  outline  = 0x0D0E10,
  bannerY  = 0xE9B90B,   -- жёлтый баннер
}

local W,H = 80,25
local buttons = {}

-- экран --------------------------------------------------------
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

-- примитивы ----------------------------------------------------
local function setfg(c) if c then gpu.setForeground(c) end end
local function setbg(c) if c then gpu.setBackground(c) end end
function core.text(x,y,s,fg) setfg(fg); gpu.set(x,y,s or "") end

function core.rect(x,y,w,h,bg,fg,char)
  setbg(bg); setfg(fg)
  for i=0,h-1 do gpu.fill(x, y+i, w, 1, char or " ") end
end

-- тонкая 1-пиксельная рамка (как на примере)
function core.frame(x,y,w,h,col)
  local prev = {gpu.getForeground()}
  gpu.setForeground(col or core.theme.border)
  if w>=2 and h>=2 then
    gpu.set(x, y,         "╭"..string.rep("─",w-2).."╮")
    gpu.set(x, y+h-1,     "╰"..string.rep("─",w-2).."╯")
    for i=1,h-2 do
      gpu.set(x,     y+i, "│")
      gpu.set(x+w-1, y+i, "│")
    end
  end
  gpu.setForeground(table.unpack(prev))
end

-- карточка с мягкой тенью (без внутренних «вторых» рамок)
function core.card_shadow(x,y,w,h,bg,border,shadow,title)
  -- лёгкая тень вправо-вниз
  core.rect(x+1,y+1,w,h, core.theme.shadow2)
  core.rect(x+2,y+2,w,h, core.theme.shadow1)
  -- фон
  core.rect(x,y,w,h, bg or core.theme.card)
  -- одинарная рамка
  core.frame(x,y,w,h, border or core.theme.border)
  if title and title~="" then core.text(x+2,y,"["..title.."]", core.theme.text) end
end

function core.card(x,y,w,h,title)
  core.card_shadow(x,y,w,h, core.theme.card, core.theme.border, core.theme.shadow2, title)
end

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

-- вертикальная шкала (без изменений)
function core.vbar(x,y,h,value,min,max,col,back)
  min,max = min or 0, max or 100
  value   = math.max(min, math.min(max, value or min))
  local fillH = math.floor((value-min)/(max-min)*h + 0.5)
  core.rect(x, y, 2, h, back or 0x1A1B1E)
  core.rect(x, y+h-fillH, 2, fillH, col or core.theme.primary)
  core.frame(x, y, 2, h, core.theme.border)
end

-- крупные «скруглённые» кнопки с тенью -------------------------
local function inside(mx,my,b) return mx>=b.x and mx<=b.x+b.w-1 and my>=b.y and my<=b.y+b.h-1 end

function core.button(x,y,w,h,label,bg,fg,onClick)
  h = math.max(3, h or 3)
  label = label or "OK"
  bg = bg or core.theme.primary
  fg = fg or 0x000000

  -- тень
  core.rect(x+1, y+1, w, h, core.theme.shadow2)

  -- тело
  core.rect(x, y, w, h, bg)

  -- имитация круглых углов (съедаем пиксели на углах)
  if w>=4 then
    setbg(bg)
    gpu.fill(x,     y,     1, 1, " ")
    gpu.fill(x+w-1, y,     1, 1, " ")
    gpu.fill(x,     y+h-1, 1, 1, " ")
    gpu.fill(x+w-1, y+h-1, 1, 1, " ")
  end

  -- тонкий контур
  core.frame(x, y, w, h, core.theme.outline)

  -- текст по центру
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

-- жёлтый баннер по центру
function core.banner_center(text)
  local w = select(1, gpu.getResolution())
  local label = text or "HAUSEGAMES"
  local bw = #label + 6
  local x = math.max(2, math.floor((w - bw)/2))
  local y = 1
  core.rect(x+1, y+1, bw, 3, core.theme.shadow2)
  core.rect(x,   y,   bw, 3, core.theme.bannerY)
  core.text(x+3, y+1, label, 0x000000)
end

function core.shutdown()
  gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
  local w,h = gpu.getResolution(); gpu.fill(1,1,w,h," "); os.exit()
end

return core

-- /lib/ugui_core.lua

local gpu = require("component").gpu

local core = {}

core.theme = {
  bg       = 0x161616,  -- общий фон
  bgPanel  = 0x1C1D20,  -- фон правых панелей/общий
  gridBg   = 0x1F2124,  -- фон области с играми
  text     = 0xEAEAEA,
  primary  = 0x00D1B2,
  border   = 0x3D8DFF,
  shadow   = 0x0D0D0D,
  card     = 0x232428,
  muted    = 0x8A8A8A,
  danger   = 0xFF5468,
}

local W,H = 80,25
local buttons = {}

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

function core.text(x,y,s,fg) if fg then gpu.setForeground(fg) end; gpu.set(x,y,s or "") end
function core.rect(x,y,w,h,bg,fg,char)
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  for i=0,h-1 do gpu.fill(x, y+i, w, 1, char or " ") end
end

function core.frame(x,y,w,h,col)
  local prev = {gpu.getForeground()}
  gpu.setForeground(col or core.theme.border)
  if w>=2 and h>=2 then
    gpu.set(x, y,         "┌"..string.rep("─",w-2).."┐")
    gpu.set(x, y+h-1,     "└"..string.rep("─",w-2).."┘")
    for i=1,h-2 do
      gpu.set(x,     y+i, "│")
      gpu.set(x+w-1, y+i, "│")
    end
  end
  gpu.setForeground(table.unpack(prev))
end

-- карточка с тенями
function core.card_shadow(x,y,w,h,bg,border,shadow,title)
  -- тень
  core.rect(x+1,y+1,w,h, shadow or core.theme.shadow)
  -- фон
  core.rect(x,y,w,h, bg or core.theme.card)
  -- рамка
  core.frame(x,y,w,h, border or core.theme.border)
  if title and title~="" then core.text(x+2,y,"["..title.."]", core.theme.text) end
end

function core.card(x,y,w,h,title) core.card_shadow(x,y,w,h, core.theme.card, core.theme.border, core.theme.shadow, title) end

function core.vbar(x,y,h,value,min,max,col,back)
  min,max = min or 0, max or 100
  value   = math.max(min, math.min(max, value or min))
  local fillH = math.floor((value-min)/(max-min)*h + 0.5)
  core.rect(x, y, 2, h, back or 0x141414)
  core.rect(x, y+h-fillH, 2, fillH, col or core.theme.primary)
  core.frame(x, y, 2, h, core.theme.border)
end

function core.logpane(x,y,w,h,lines)
  core.card_shadow(x,y,w,h, core.theme.card, core.theme.border, core.theme.shadow)
  if not lines then return end
  local maxLines = h-2
  local start = math.max(1, #lines - maxLines + 1)
  local cy = y+1
  for i=start,#lines do
    local s = tostring(lines[i]); if #s>w-2 then s=s:sub(1,w-5).."..." end
    core.text(x+1, cy, s, core.theme.muted); cy = cy + 1
  end
end

-- кнопки
local function inside(mx,my,b) return mx>=b.x and mx<=b.x+b.w-1 and my>=b.y and my<=b.y+b.h-1 end
function core.button(x,y,w,h,label,bg,fg,onClick)
  core.rect(x,y,w,h, bg or core.theme.primary, fg or 0x000000)
  core.frame(x,y,w,h, fg or 0x000000)
  if label and label~="" then
    local tx = x + math.floor((w-#label)/2)
    local ty = y + math.floor(h/2)
    core.text(tx,ty,label, fg or 0x000000)
  end
  local b = {x=x,y=y,w=w,h=h,onClick=onClick}; table.insert(buttons,b); return b
end
function core.inBounds(ctrl,x,y) return ctrl and inside(x,y,ctrl) or false end
function core.dispatch_click(x,y)
  for _,b in ipairs(buttons) do if inside(x,y,b) then if b.onClick then pcall(b.onClick) end; return true end end
  return false
end

function core.shutdown()
  gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
  local w,h = gpu.getResolution(); gpu.fill(1,1,w,h," "); os.exit()
end

return core

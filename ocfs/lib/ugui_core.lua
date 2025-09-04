-- /lib/ugui_core.lua
-- минималистичный рендер-движок для красивого GUI в OpenComputers
local component = require("component")
local event     = require("event")
local gpu       = component.gpu
local unicode   = require("unicode")

local U = {}

-- init screen
local maxW, maxH = gpu.maxResolution()
gpu.setResolution(maxW, maxH)
gpu.setBackground(0x1b1b1b)
gpu.setForeground(0xffffff)

-- double buffer --------------------------------------------------------------
local function newBuf(w,h, bg, fg, ch)
  local b = {w=w,h=h,bg={},fg={},ch={}}
  for y=1,h do
    b.bg[y], b.fg[y], b.ch[y] = {}, {}, {}
    for x=1,w do
      b.bg[y][x]=bg or 0x000000
      b.fg[y][x]=fg or 0xffffff
      b.ch[y][x]=ch or ' '
    end
  end
  return b
end

local scrW, scrH = gpu.getResolution()
local B = newBuf(scrW, scrH, 0x141414, 0xffffff, ' ')

function U.clear(color)
  for y=1,B.h do
    for x=1,B.w do
      B.bg[y][x]=color or 0x141414
      B.fg[y][x]=0xffffff
      B.ch[y][x]=' '
    end
  end
end

local function pset(x,y,ch,fg,bg)
  if x<1 or y<1 or x>B.w or y>B.h then return end
  B.ch[y][x] = ch or ' '
  if fg then B.fg[y][x]=fg end
  if bg then B.bg[y][x]=bg end
end

function U.flush()
  local lastBG, lastFG = -1,-1
  for y=1,B.h do
    local run=1
    while run<=B.w do
      local bg, fg = B.bg[y][run], B.fg[y][run]
      if bg~=lastBG then gpu.setBackground(bg); lastBG=bg end
      if fg~=lastFG then gpu.setForeground(fg); lastFG=fg end
      local x0=run
      local s={}
      while run<=B.w and B.bg[y][run]==bg and B.fg[y][run]==fg do
        s[#s+1]=B.ch[y][run]
        run=run+1
      end
      gpu.set(x0,y,table.concat(s))
    end
  end
end

-- drawing helpers ------------------------------------------------------------
function U.rect(x,y,w,h,bg,fg,ch)
  for yy=y,y+h-1 do
    for xx=x,x+w-1 do
      pset(xx,yy,ch or ' ',fg,bg)
    end
  end
end

function U.shadow(x,y,w,h,color)
  local c=color or 0x000000
  for xx=x+1,x+w do pset(xx,y+h,' ',nil,c) end
  for yy=y+1,y+h do pset(x+w,yy,' ',nil,c) end
end

function U.frame(x,y,w,h,col)
  local c=col or 0x2a2a2a
  for xx=x,x+w-1 do pset(xx,y,'─',c); pset(xx,y+h-1,'─',c) end
  for yy=y,y+h-1 do pset(x,yy,'│',c); pset(x+w-1,yy,'│',c) end
  pset(x,y,'┌',c); pset(x+w-1,y,'┐',c); pset(x,y+h-1,'└',c); pset(x+w-1,y+h-1,'┘',c)
end

function U.text(x,y,s,col)
  if not s then return end
  for i=1,unicode.len(s) do
    pset(x+i-1,y,unicode.sub(s,i,i),col)
  end
end

-- theme ----------------------------------------------------------------------
U.theme = {
  bg      = 0x1b1b1b,
  panel   = 0x242424,
  card    = 0x202226,
  cardHi  = 0x2a2d33,
  shadow  = 0x000000,
  text    = 0xe6e6e6,
  dim     = 0xa0a0a0,
  primary = 0x00C6FF, -- голубой
  danger  = 0xff5067, -- красный
  warn    = 0xFFD166, -- жёлтый
  ok      = 0x2EEA8C, -- зелёный
}

-- widgets --------------------------------------------------------------------
function U.card(x,y,w,h,title)
  U.shadow(x,y,w,h,0x000000)
  U.rect(x,y,w,h,U.theme.card)
  U.frame(x,y,w,h,0x31343a)
  if title then
    U.text(x+2,y," "..title.." ",0xffffff)
  end
end

function U.kpi(x,y,label,value,iconCol)
  U.text(x,y,label,U.theme.dim)
  U.text(x,y+1,value,iconCol or U.theme.text)
end

function U.vbar(x,y,h,value,min,max,barCol,backCol)
  min,max=min or 0,max or 100
  local pct=0
  if max>min then pct=math.max(0,math.min(1,(value-min)/(max-min))) end
  local fill=math.floor(h*pct+0.5)
  for i=0,h-1 do
    local col=(i>=h-fill) and (barCol or U.theme.primary) or (backCol or 0x303030)
    pset(x,y+h-1-i,' ',nil,col)
  end
end

function U.button(x,y,w,h,label,colBG,colText)
  U.rect(x,y,w,h,colBG or U.theme.primary)
  U.frame(x,y,w,h,0x000000)
  local tx=x+math.floor((w-unicode.len(label))/2)
  local ty=y+math.floor(h/2)
  U.text(tx,ty,label,colText or 0x000000)
  return {x=x,y=y,w=w,h=h,label=label}
end

function U.inBounds(ctrl,cx,cy)
  return cx>=ctrl.x and cy>=ctrl.y and cx<ctrl.x+ctrl.w and cy<ctrl.y+ctrl.h
end

function U.logpane(x,y,w,h,lines)
  U.card(x,y,w,h,"")
  local maxLines=h-2
  local start=math.max(1,#lines-maxLines+1)
  for i=0,math.min(maxLines-1,#lines-1) do
    U.text(x+2,y+1+i,lines[start+i+1],U.theme.dim)
  end
end

return U

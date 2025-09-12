-- rcui.lua — UI-библиотека для OpenComputers (двойная буферизация + брайлевый псевдографический UI)
-- Требования: doubleBuffering, image, event, unicode, bit32, component (опц.), filesystem (опц.)
-- Авторство исходного дизайна интерфейса вдохновлено кодом Reactor Control by P1KaChU337.
-- Библиотека — независимая и переиспользуемая, без хардкода логики реакторов.

local rcui = {}

-- ======= DEPENDS =======
local computer = require("computer")
local buffer   = require("doubleBuffering")
local image    = require("image")
local event    = require("event")
local unicode  = require("unicode")
local bit      = require("bit32")
local fs       = require("filesystem")
local component= require("component")

-- ======= INTERNAL STATE =======
local STATE = {
  W = 160, H = 50,
  theme = "dark", -- "dark" | "light"
  bgImages = { dark = nil, light = nil }, -- пути к картинкам
  lastUptime = computer.uptime(),
  exit = false,
  schedule = {}, -- { {period, last, fn}, ... }
  clickAreas = {}, -- { {x1,y1,x2,y2, cb, id}, ... }
  widgets = {}, -- все виджеты (рисуются и получают клики)
  dirty = true, -- invalidate-семафор
  metric = 0,  -- 0=Auto, 1=base, 2=k, 3=M, 4=G
  console = nil,
  marquee = nil,
  panels = {},
  colors = {},  -- актуальная цветовая палитра темы
  logFile = "/home/rcui_errors.log",
}

-- ======= THEME =======
local THEMES = {
  dark = {
    bg   = 0x202020,
    bg2  = 0x101010,
    bg3  = 0x3c3c3c,
    frame= 0x969696,
    accent=0x059bff,
    text = 0xcccccc,
    textDim = 0x9a9a9a,
    btnText = 0xffffff,
    ok   = 0x61ff52,
    warn = 0xfff700,
    err  = 0xff0000,
    whitebtn2=0x38afff,
  },
  light = {
    bg   = 0x000000,
    bg2  = 0x202020,
    bg3  = 0xffffff,
    frame= 0x5a5a5a,
    accent=0x059bff,
    text = 0x303030,
    textDim = 0x5a5a5a,
    btnText = 0x303030,
    ok   = 0x61ff52,
    warn = 0xfff700,
    err  = 0xff0000,
    whitebtn2=0x38afff,
  }
}

local function setTheme(name)
  STATE.theme = (name == true or name == "light") and "light" or "dark"
  STATE.colors = THEMES[STATE.theme]
  rcui.invalidate()
end

-- ======= UTILS =======
local function clamp(v, a, b) if v<a then return a elseif v>b then return b else return v end end
local function lerp(a,b,t) return a + (b-a)*t end
local function lerpColor(c1, c2, t)
  local r1,g1,b1 = bit.rshift(c1,16)%0x100, bit.rshift(c1,8)%0x100, c1%0x100
  local r2,g2,b2 = bit.rshift(c2,16)%0x100, bit.rshift(c2,8)%0x100, c2%0x100
  return bit.lshift(math.floor(lerp(r1,r2,t)),16)+bit.lshift(math.floor(lerp(g1,g2,t)),8)+math.floor(lerp(b1,b2,t))
end
local function round(n, d) local m=10^(d or 0); local r=math.floor(n*m+0.5)/m; return (r==math.floor(r)) and tostring(math.floor(r)) or tostring(r) end

function rcui.safeCall(proxy, method, default, ...)
  if proxy and proxy[method] then
    local ok, res = pcall(proxy[method], proxy, ...)
    if ok and res ~= nil then
      if type(default) == "number" then
        local num = tonumber(res); if num then return num end
        local f = io.open(STATE.logFile,"a"); if f then f:write(string.format("[%s] non-number: %s -> %s\n", os.date(), method, tostring(res))); f:close() end
        return default
      else
        return res
      end
    else
      local f = io.open(STATE.logFile,"a"); if f then f:write(string.format("[%s] call error: %s => %s\n", os.date(), tostring(method), tostring(res))); f:close() end
      return default
    end
  end
  return default
end

function rcui.invalidate() STATE.dirty = true end

-- ======= METRICS FORMATTERS =======
local METRIC_LABELS = {
  rf  = { base="Rf", k="kRf", m="mRf", g="gRf" },
  mb  = { base="Mb", k="kMb", m="mMb", g="gMb" },
}

local function formatMetric(value, mode, labels)
  value = tonumber(value) or 0
  if mode == 0 then -- Auto
    if value >= 1e9 then return round(value/1e9,1), labels.g
    elseif value >= 1e6 then return round(value/1e6,1), labels.m
    elseif value >= 1e3 then return round(value/1e3,1), labels.k
    else return round(value,1), labels.base end
  elseif mode == 1 then return round(value,1), labels.base
  elseif mode == 2 then return round(value/1e3,1), labels.k
  elseif mode == 3 then return round(value/1e6,1), labels.m
  else return round(value/1e9,1), labels.g end
end

function rcui.metricMode() return STATE.metric end
function rcui.setMetric(mode) STATE.metric = clamp(tonumber(mode) or 0, 0, 4); rcui.invalidate() end
function rcui.nextMetric()
  STATE.metric = STATE.metric + 1
  if STATE.metric > 4 then STATE.metric = 0 end
  rcui.invalidate()
  return STATE.metric
end
function rcui.formatRF(v)  return formatMetric(v, STATE.metric, METRIC_LABELS.rf) end
function rcui.formatMb(v)  return formatMetric(v, STATE.metric, METRIC_LABELS.mb) end
function rcui.formatFluxRF(value) -- спец: красивый текст и юнит
  value = tonumber(value) or 0
  local unit = "Rf"
  local i=1; local suffix={"Rf","kRf","mRf","gRf"}
  while value>=1000 and i<#suffix do value=value/1000; i=i+1 end
  local s = (value<10) and string.format("%.2f",value) or (value<100) and string.format("%.1f",value) or string.format("%.0f",value)
  s=s:gsub("%.0$","")
  return s, suffix[i]
end

-- ======= BRAILLE “FONT” =======
local function brailleChar(dots)
  return unicode.char(
    10240 + (dots[8] or 0)*128 + (dots[7] or 0)*64 + (dots[6] or 0)*32 +
             (dots[4] or 0)*16 + (dots[2] or 0)*8  + (dots[5] or 0)*4 +
             (dots[3] or 0)*2  + (dots[1] or 0))
end

-- цифры/символы (4 клетки: 2x2 символа брайл)
local DIGITS = {
  [0]={{1,1,1,0,1,0,1,0},{1,0,1,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}},
  [1]={{0,1,1,1,0,1,0,1},{0,0,0,0,0,0,0,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}},
  [2]={{1,1,0,0,1,1,1,0},{1,0,1,0,1,0,0,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}},
  [3]={{1,1,0,0,1,1,0,0},{1,0,1,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}},
  [4]={{1,0,1,0,1,1,0,0},{1,0,1,0,1,0,1,0},{0,0,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}},
  [5]={{1,1,1,0,1,1,0,0},{1,0,0,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}},
  [6]={{1,1,1,0,1,1,1,0},{1,0,0,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}},
  [7]={{1,1,0,0,0,0,0,0},{1,0,1,0,1,0,1,0},{0,0,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}},
  [8]={{1,1,1,0,1,1,1,0},{1,0,1,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}},
  [9]={{1,1,1,0,1,1,0,0},{1,0,1,0,1,0,1,0},{1,1,0,0,0,0,0,0},{1,0,0,0,0,0,0,0}},
  ["-"]={{0,0,0,0,1,1,0,0},{0,0,0,0,1,0,0,0},{0,0,0,0,0,0,0,0},{0,0,0,0,0,0,0,0}},
  ["."]={{0,0,0,0,0,0,0,0},{0,0,0,0,0,0,0,0},{1,0,0,0,0,0,0,0},{0,0,0,0,0,0,0,0}},
}

local VBAR = {
  {0,0,0,0,0,0,1,1},
  {0,0,0,0,1,1,1,1},
  {0,0,1,1,1,1,1,1},
  {1,1,1,1,1,1,1,1},
}

local function drawDigit(x,y,b,color)
  buffer.drawText(x, y    , color, brailleChar(b[1]))
  buffer.drawText(x, y + 1, color, brailleChar(b[3]))
  buffer.drawText(x+1,y   , color, brailleChar(b[2]))
  buffer.drawText(x+1,y+1 , color, brailleChar(b[4]))
end

function rcui.drawNumberWithText(cx, cy, str, digitW, color, suffix, suffixColor)
  suffixColor = suffixColor or color
  local digits, widths = {}, {}
  local s = tostring(str)
  for i=1,#s do
    local ch = s:sub(i,i); local n = tonumber(ch)
    if n then table.insert(digits, DIGITS[n]); table.insert(widths, digitW)
    elseif DIGITS[ch] then table.insert(digits, DIGITS[ch]); table.insert(widths, (ch==".") and 1 or digitW) end
  end
  local suffW = (suffix and #suffix or 0)
  local total=0; for _,w in ipairs(widths) do total=total+w end
  total = total + ((suffW>0) and (suffW+1) or 0)
  local x = math.floor(cx - total/2)
  buffer.drawText(x, cy, STATE.colors.bg, string.rep(" ", total))
  local cur=x
  for i,d in ipairs(digits) do drawDigit(cur, cy, d, color); cur=cur+widths[i] end
  if suffix and suffW>0 then buffer.drawText(cur, cy, suffixColor, suffix) end
end

function rcui.drawVerticalProgressBar(x, y, height, value, maxValue, colorBottom, colorTop, colorInactive)
  maxValue = (maxValue and maxValue>0) and maxValue or 1
  value = clamp(tonumber(value) or 0, 0, maxValue)
  local totalParts = height*4
  local filled = math.floor(totalParts * (value/maxValue))
  buffer.drawRectangle(x, y, 1, height, colorInactive or STATE.colors.bg2, 0, " ")
  local full = math.floor(filled/4)
  local rem  = filled%4
  for i=0,full-1 do
    local pos = (i+1)/height
    local clr = lerpColor(colorBottom, colorTop, pos)
    buffer.drawText(x, y + height - i - 1, clr, brailleChar(VBAR[4]))
  end
  if rem>0 then
    local pos = (full+1)/height
    local clr = lerpColor(colorBottom, colorTop, pos)
    buffer.drawText(x, y + height - full - 1, clr, brailleChar(VBAR[rem]))
  end
end

-- ======= BUTTON =======
local BTN = {
  edgeTop    = {0,0,0,0,1,1,1,1},
  edgeTopIn  = {0,0,0,0,1,0,1,1},
  edgeBot    = {1,1,1,1,0,0,0,0},
  edgeLeft   = {0,0,0,0,0,1,1,1},
  edgeRight  = {0,0,0,0,0,1,1,0},
}

local function shortenCentered(text, width)
  local len = unicode.len(text)
  if len>width then
    text = unicode.sub(text,1,width-3).."..."
    len = unicode.len(text)
  end
  local pad = math.floor((width - len)/2)
  return string.rep(" ", math.max(pad,0))..text
end

local Widget = {} ; Widget.__index = Widget
function Widget:new(kind, geom, drawFn, onClick)
  return setmetatable({
    kind=kind, x=geom.x, y=geom.y, w=geom.w, h=geom.h,
    drawFn=drawFn, onClick=onClick, visible=true, cache=nil, dirty=true
  }, self)
end
function Widget:contains(px,py) return self.visible and px>=self.x and py>=self.y and px<=self.x+self.w-1 and py<=self.y+self.h-1 end
function Widget:draw()
  if not self.visible then return end
  if self.drawFn then self.drawFn(self) end
  self.dirty=false
end
function Widget:setDirty() self.dirty=true; rcui.invalidate() end

function rcui.button(x, y, width, label, opts)
  opts = opts or {}
  local h = 3
  local c = opts.color or STATE.colors.accent
  local t = opts.textColor or STATE.colors.btnText
  local onClick = opts.onClick
  local btn = Widget:new("button", {x=x,y=y,w=width,h=h},
    function(self)
      -- рамка + заливка центра
      buffer.drawText(self.x-1, self.y  , c, brailleChar(BTN.edgeLeft))
      buffer.drawText(self.x+self.w, self.y  , c, brailleChar(BTN.edgeRight))
      buffer.drawText(self.x-1, self.y+2, c, brailleChar(BTN.edgeLeft))
      buffer.drawText(self.x+self.w, self.y+2, c, brailleChar(BTN.edgeRight))
      for i=0,self.w-1 do
        buffer.drawText(self.x+i,self.y,c,brailleChar(BTN.edgeTop))
        buffer.drawText(self.x+i,self.y+2,c,brailleChar(BTN.edgeBot))
      end
      buffer.drawRectangle(self.x, self.y+1, self.w, 1, c, 0, " ")
      buffer.drawText(self.x, self.y+1, t, shortenCentered(label, self.w))
    end,
    function(self)
      -- клик-анимация
      buffer.drawRectangle(self.x, self.y+1, self.w, 1, c, 0, " ")
      buffer.drawText(self.x, self.y+1, t, shortenCentered(label, self.w))
      buffer.drawChanges(); os.sleep(0.06)
      if onClick then onClick(self) end
    end
  )
  table.insert(STATE.widgets, btn)
  rcui.registerClickArea(x-1, y, x+width, y+2, function() btn.onClick(btn) end, btn)
  return btn
end

-- ======= CONSOLE (правое окно логов с переносом и стэкингом) =======
local function utf8len(s) local _,c = s:gsub("[^\128-\191]",""); return c end
local function utf8sub(str,startChar,numChars)
  local startIndex=1
  while startChar>1 do
    local c=str:byte(startIndex); if not c then break end
    if c<128 or c>=192 then startChar=startChar-1 end; startIndex=startIndex+1
  end
  local cur=startIndex
  while numChars>0 and cur<=#str do
    local c=str:byte(cur); if not c then break end
    if c<128 or c>=192 then numChars=numChars-1 end
    cur=cur+1
  end
  return str:sub(startIndex,cur-1)
end

local Console = {} ; Console.__index=Console
function Console:new(x,y,w,h, textColor)
  local o = setmetatable({
    x=x,y=y,w=w,h=h, lines={}, textColor=textColor or STATE.colors.text, limit=w-1
  }, self)
  return o
end
function Console:wrap(msg, limit)
  limit = limit or self.limit
  local res={}
  while utf8len(msg)>limit do
    local chunk = utf8sub(msg,1,limit)
    local spacePos = chunk:match(".*()%s")
    if spacePos then table.insert(res, msg:sub(1, spacePos-1)); msg=msg:sub(spacePos+1)
    else table.insert(res, utf8sub(msg,1,limit-1).."-"); msg=utf8sub(msg,limit) end
  end
  if utf8len(msg)>0 then table.insert(res,msg) end
  return res
end
function Console:push(msg, color, nostack)
  msg=tostring(msg or "")
  local parts=self:wrap(msg, self.limit)
  if not nostack then
    -- попытка стэкинга одинаковых сообщений
    for i=#self.lines,1,-1 do
      local L=self.lines[i]
      if L and L.textBase==msg then
        L.count=(L.count or 1)+1
        local lastPart = parts[#parts].."(x"..L.count..")"
        if utf8len(lastPart)<=self.limit then
          self.lines[i].text=lastPart
          for j=1,#parts-1 do
            local idx=i-(#parts-j)
            if self.lines[idx] then self.lines[idx].text=parts[j] end
          end
          rcui.invalidate()
          return
        end
        break
      end
    end
  end
  for _,p in ipairs(parts) do
    table.insert(self.lines, {text=p, textBase=msg, color=color or self.textColor, count=1})
  end
  while #self.lines>self.h do table.remove(self.lines,1) end
  rcui.invalidate()
end
function Console:draw()
  local c=STATE.colors
  buffer.drawRectangle(self.x, self.y, self.w, self.h, c.bg, 0, " ")
  for i=1,#self.lines do
    buffer.drawText(self.x, self.y-1+i, self.lines[i].color or c.text, self.lines[i].text or "")
  end
end

function rcui.createConsole(x,y,w,h, color)
  STATE.console = Console:new(x,y,w,h,color)
  return STATE.console
end
function rcui.message(msg, col, nostack) if STATE.console then STATE.console:push(msg, col, nostack) end end

-- ======= MARQUEE =======
local Marquee = {} ; Marquee.__index=Marquee
function Marquee:new(x,y,width,text,color)
  return setmetatable({x=x,y=y,w=width or 30, text=text or "", color=color or 0xF15F2C, pos=1}, self)
end
function Marquee:setText(t) self.text=t or ""; self.pos=1; rcui.invalidate() end
function Marquee:tick()
  local txt=self.text; local L = unicode.len(txt)
  if L<=self.w then return end
  local vis = unicode.sub(txt, self.pos, self.pos+self.w-1)
  local vlen = unicode.len(vis)
  if vlen<self.w then
    vis = vis .. unicode.sub(txt, 1, self.w - vlen)
  end
  buffer.drawText(self.x, self.y, self.color, vis)
  self.pos = self.pos + 1; if self.pos>L then self.pos=1 end
end

function rcui.createMarquee(x,y,width, text, color)
  STATE.marquee = Marquee:new(x,y,width,text,color)
  rcui.every(0.1, function() if STATE.marquee then STATE.marquee:tick(); buffer.drawChanges() end end)
  return STATE.marquee
end

-- ======= PANELS (правый столбец) =======
local function panelRect(x,y,w,h) return Widget:new("panel",{x=x,y=y,w=w,h=h}, function(self)
  buffer.drawRectangle(self.x, self.y, self.w, self.h, STATE.colors.bg, 0, " ")
end) end

function rcui.createPanel(x,y,w,h, drawFn)
  local p = Widget:new("panel",{x=x,y=y,w=w,h=h}, function(self) 
    buffer.drawRectangle(self.x,self.y,self.w,self.h,STATE.colors.bg,0," ")
    if drawFn then drawFn(self) end
  end)
  table.insert(STATE.widgets,p)
  return p
end

-- готовые мини-панели (передай функции-поставщики данных)
function rcui.statusPanel(opts)
  local x,y,w,h = opts.x,opts.y, opts.w or 31, opts.h or 6
  local get = opts.get -- fn -> {reactors=N, anyOn=bool, consumeMb=number}
  return rcui.createPanel(x,y,w,h, function(self)
    local c=STATE.colors
    buffer.drawText(x+1,y, c.text, "Статус комплекса:")
    local info = get and get() or {reactors=0, anyOn=false, consumeMb=0}
    buffer.drawText(x+1,y+2, c.text, "Кол-во реакторов: "..tostring(info.reactors))
    buffer.drawText(x+1,y+3, c.text, "Общее потребление")
    local val,unit = rcui.formatMb(info.consumeMb or 0)
    buffer.drawText(x+1,y+4, c.text, ("жидкости: %s %s/s"):format(val,unit))
    local ok = info.anyOn
    local boxX=x+w-9; local boxY=y+2
    local color = ok and c.ok or c.err
    buffer.drawRectangle(boxX, boxY+1, 6, 1, color,0," ")
    buffer.drawRectangle(boxX+1, boxY, 4, 3, color,0," ")
    buffer.drawText(boxX+1, boxY+1, ok and 0x0d9f00 or 0x9d0000, ok and "Work" or "Stop")
  end)
end

function rcui.rfPanel(opts)
  local x,y,w,h = opts.x,opts.y, opts.w or 35, opts.h or 4
  local get = opts.get -- fn-> totalRF number
  return rcui.createPanel(x,y,w,h, function(self)
    local c=STATE.colors
    buffer.drawText(x+1,y, c.text, "Генерация всех реакторов:")
    local total = get and (tonumber(get()) or 0) or 0
    local val,unit = rcui.formatRF(total)
    rcui.drawNumberWithText(x+21, y+2, val, 2, c.text, unit.."/t", c.text)
  end)
end

function rcui.fluidPanel(opts)
  local x,y,w,h = opts.x,opts.y, opts.w or 35, opts.h or 4
  local get = opts.get -- fn-> mB number
  local label = opts.label or "Жидкости в МЭ сети:"
  return rcui.createPanel(x,y,w,h, function(self)
    local c=STATE.colors
    buffer.drawText(x+1,y, c.text, label)
    local count = get and (tonumber(get()) or 0) or 0
    local val,unit = rcui.formatMb(count)
    rcui.drawNumberWithText(x+20, y+2, val, 2, c.text, unit, c.text)
  end)
end

function rcui.fluxPanel(opts)
  local x,y,w,h = opts.x,opts.y, opts.w or 35, opts.h or 4
  local get = opts.get -- fn-> {in=rf, out=rf}
  return rcui.createPanel(x,y,w,h, function(self)
    local c=STATE.colors
    buffer.drawText(x+1,y, c.text, "Общий вход/выход в Flux сети:")
    local info = get and get() or {["in"]=0,out=0}
    local vin,uin = rcui.formatFluxRF(info["in"] or 0)
    local vout,uout = rcui.formatFluxRF(info["out"] or 0)
    rcui.drawNumberWithText(x+13, y+2, vin, 2, c.text, uin.."/t", c.text)
    rcui.drawNumberWithText(x+29, y+2, vout,2, c.text, uout.."/t", c.text)
  end)
end

function rcui.thresholdPanel(opts)
  local x,y,w,h = opts.x,opts.y, opts.w or 35, opts.h or 4
  local get, set = opts.get, opts.set
  local step = opts.step or 2500
  return rcui.createPanel(x,y,w,h, function(self)
    local c=STATE.colors
    buffer.drawText(x+1,y, c.text, "Настройка порога жидкости:")
    -- "+" и "-" как кликабельные мини-зоны 2х2
    buffer.drawText(x+1, y+2, 0xa6ff00, brailleChar({0,0,0,1,1,1,0,1}))
    buffer.drawText(x+3, y+2, 0xff2121, brailleChar({0,0,0,0,0,1,0,0}))
    local val = get and (tonumber(get()) or 0) or 0
    rcui.drawNumberWithText(x+21, y+2, val, 2, c.text, "Mb", c.text)
  end)
  :setDirty()
end

-- мини-хит зоны для threshold (+/-)
function rcui.attachThresholdControls(xPlus,yPlus,xMinus,yMinus, get,set, step)
  step = step or 2500
  rcui.registerClickArea(xPlus, yPlus, xPlus, yPlus, function()
    set( (get() or 0) + step ); rcui.invalidate()
  end, "porog+")
  rcui.registerClickArea(xMinus, yMinus, xMinus, yMinus, function()
    local v= (get() or 0) - step; if v<0 then v=0 end; set(v); rcui.invalidate()
  end, "porog-")
end

-- ======= WIDGET: REACTOR CARD (универсальный карточный виджет) =======
function rcui.reactorCard(x, y, getData, onToggle)
  -- getData() -> {index=i, temp=°C, rf=RFt, type="Fluid"/"Air", work=bool, depl=sec, cool=cur, coolMax=max}
  local c = STATE.colors
  local w = Widget:new("reactor", {x=x,y=y,w=22,h=11}, function(self)
    local d = getData and getData() or {}
    buffer.drawRectangle(x+1,y,20,11,c.bg,0," ")
    buffer.drawRectangle(x,  y+1,22,9,c.bg,0," ")
    -- рамка углами можно стилизовать: оставим простую заливку и текст
    buffer.drawText(x+6,y+1,c.text, "Реактор #"..(d.index or "?"))
    buffer.drawText(x+4,y+3,c.text, "Нагрев: "..(d.temp or 0).."°C")
    buffer.drawText(x+4,y+4,c.text, "Ген: "..(rcui.formatRF(d.rf or 0)))
    buffer.drawText(x+4,y+5,c.text, "Тип: "..(d.type or "-"))
    buffer.drawText(x+4,y+6,c.text, "Запущен: "..(d.work and "Да" or "Нет"))
    local tsec = tonumber(d.depl or 0) or 0
    local hrs = math.floor(tsec/3600); local mins = math.floor((tsec%3600)/60); local secs=tsec%60
    buffer.drawText(x+4,y+7,c.text, string.format("Распад: %02d:%02d:%02d",hrs,mins,secs))
    local btnLabel = d.work and "Отключить" or "Включить"
    rcui.button(x+6, y+8, 10, btnLabel, {color=d.work and 0xfd3232 or 0x2beb1a, onClick=function() if onToggle then onToggle(d.index) end end})
    if d.type=="Fluid" then
      rcui.drawVerticalProgressBar(x+1, y+1, 9, d.cool or 0, d.coolMax or 1, 0x0044FF, 0x00C8FF, c.bg2)
    end
  end)
  table.insert(STATE.widgets, w)
  return w
end

-- ======= BACKGROUND =======
function rcui.setBackgroundImages(darkPath, lightPath)
  STATE.bgImages.dark  = darkPath
  STATE.bgImages.light = lightPath or darkPath
end

local function drawBackground()
  local path = (STATE.theme=="dark") and STATE.bgImages.dark or STATE.bgImages.light
  if path and fs.exists(path) then
    local pic = image.load(path); if pic then buffer.drawImage(1,1,pic) end
  else
    buffer.drawRectangle(1,1,STATE.W,STATE.H, STATE.colors.bg,0," ")
  end
end

-- ======= CLICK AREAS & WIDGET DISPATCH =======
function rcui.registerClickArea(x1,y1,x2,y2, cb, id)
  table.insert(STATE.clickAreas, {x1=x1,y1=y1,x2=x2,y2=y2, cb=cb, id=id})
end

local function dispatchClick(x,y)
  -- сначала проверяем виджеты (у которых onClick и hit-test), потом clickAreas
  for i=#STATE.widgets,1,-1 do
    local w=STATE.widgets[i]
    if w.onClick and w:contains(x,y) then w.onClick(w); return end
  end
  for _,a in ipairs(STATE.clickAreas) do
    if x>=a.x1 and y>=a.y1 and x<=a.x2 and y<=a.y2 then if a.cb then a.cb() end; return end
  end
end

-- ======= SCHEDULER =======
function rcui.every(period, fn) table.insert(STATE.schedule, {period=period, last=computer.uptime(), fn=fn}) end

local function tickScheduler()
  local now = computer.uptime()
  for _,t in ipairs(STATE.schedule) do
    if now - t.last >= t.period then
      t.last = now
      local ok,err = pcall(t.fn)
      if not ok then local f=io.open(STATE.logFile,"a"); if f then f:write(string.format("[%s] task error: %s\n", os.date(), tostring(err))); f:close() end end
    end
  end
end

-- ======= LAYOUT HELPERS =======
function rcui.grid12()
  -- возвращает координаты 12 виджетов как в оригинале
  local w = {
    {10,6}, {36,6}, {65,6}, {91,6},
    {10,18},{36,18},{65,18},{91,18},
    {10,30},{36,30},{65,30},{91,30}
  }
  return w
end

-- ======= PUBLIC: INIT / RENDER / LOOP =======
function rcui.init(opts)
  opts = opts or {}
  STATE.W, STATE.H = opts.w or 160, opts.h or 50
  buffer.setResolution(STATE.W, STATE.H)
  buffer.clear(0x000000)
  setTheme(opts.theme or "dark")
  if opts.bgDark or opts.bgLight then rcui.setBackgroundImages(opts.bgDark, opts.bgLight) end
  if opts.metric ~= nil then rcui.setMetric(opts.metric) end
  return rcui
end

function rcui.draw()
  if not STATE.dirty then return end
  drawBackground()
  -- нарисовать все зарегистрированные виджеты
  for _,w in ipairs(STATE.widgets) do w:draw() end
  -- консоль в конце, чтобы текст не “прибило”
  if STATE.console then STATE.console:draw() end
  buffer.drawChanges()
  STATE.dirty=false
end

function rcui.run(loop)
  -- loop() — твой апдейт-обработчик (сбор данных, invalidate по необходимости)
  while not STATE.exit do
    tickScheduler()
    if loop then loop() end
    rcui.draw()
    local ev = {event.pull(0.05)}
    if ev[1]=="touch" then local _,_,x,y = table.unpack(ev); dispatchClick(x,y) end
    os.sleep(0)
  end
end

function rcui.stop() STATE.exit=true end
function rcui.setTheme(val) setTheme(val) end
function rcui.colors() return STATE.colors end

return rcui

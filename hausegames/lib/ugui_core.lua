-- /lib/ugui_core.lua — reactor/minecraft стиль (v3.1)

local gpu     = require("component").gpu
local unicode = require("unicode")
local core = {}

-- палитра
core.theme = {
  -- фоны
  bg            = 0x343434,  -- общий тёмно-серый
  gridBg        = 0xB5B5B5,  -- светло-серый внутри большого поля
  gridEdgeDark  = 0x6A6A6A,  -- внешний слой толстой рамки (1px)
  gridEdgeLight = 0x8E8E8E,  -- внутренний слой толстой рамки (1px)

  -- карточки/панели/текст
  card     = 0x151719,
  panelBg  = 0x2E3033,
  text     = 0xE8EBEF,
  muted    = 0xBFC4CA,

  -- акценты
  border   = 0x6D77FF,       -- тонкая синяя рамка для правых панелей
  primary  = 0x12D4C6,
  danger   = 0xFF7C8F,

  -- тени/контуры
  shadow1  = 0x25272A,       -- мягкая 1px тень (внутренняя)
  outline  = 0x0E0F11,       -- резерв (не используется на кнопках/карточках)

  -- заголовок
  titleGray   = 0xD0D0D0,
  titleYellow = 0xF0B915,
  titleCheek  = 0x8E8E8E,
}

local W,H = 80,25
local buttons = {}

-- экран ---------------------------------------------------------
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

-- примитивы -----------------------------------------------------
local function setfg(c) if c then gpu.setForeground(c) end end
local function setbg(c) if c then gpu.setBackground(c) end end
function core.text(x,y,s,fg) setfg(fg); gpu.set(x,y,s or "") end
function core.rect(x,y,w,h,bg,fg,char)
  setbg(bg); if fg then gpu.setForeground(fg) end
  for i=0,h-1 do gpu.fill(x, y+i, w, 1, char or " ") end
end

-- тонкая рамка (для правых панелей)
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

-- большой квадратный двухцветный фрейм
function core.big_grid_frame(x,y,w,h)
  core.rect(x,   y,      w,   1, core.theme.gridEdgeDark)
  core.rect(x,   y+h-1,  w,   1, core.theme.gridEdgeDark)
  core.rect(x,   y,      1,   h, core.theme.gridEdgeDark)
  core.rect(x+w-1,y,     1,   h, core.theme.gridEdgeDark)

  core.rect(x+1, y+1,    w-2, 1, core.theme.gridEdgeLight)
  core.rect(x+1, y+h-2,  w-2, 1, core.theme.gridEdgeLight)
  core.rect(x+1, y+1,    1,   h-2, core.theme.gridEdgeLight)
  core.rect(x+w-2,y+1,   1,   h-2, core.theme.gridEdgeLight)

  core.rect(x+2, y+2,    w-4, h-4, core.theme.gridBg)
end

-- мягкая внутренняя тень: 1px снизу и справа, НЕ выходит за границы
local function inner_shadow(x,y,w,h)
  if w>=3 then core.rect(x+1, y+h-1, w-2, 1, core.theme.shadow1) end  -- низ
  if h>=3 then core.rect(x+w-1, y+1, 1,   h-2, core.theme.shadow1) end -- правая грань
end

-- «пиксельные» скругления через срез углов
local function cut_corners(x,y,w,h,bg)
  if w>=4 and h>=3 then
    setbg(bg)
    gpu.fill(x,     y,     1, 1, " ")
    gpu.fill(x+w-1, y,     1, 1, " ")
    gpu.fill(x,     y+h-1, 1, 1, " ")
    gpu.fill(x+w-1, y+h-1, 1, 1, " ")
  end
end

-- правые панели: фон + рамка + внутренняя маленькая тень
function core.card_shadow(x,y,w,h,bg,border,_,title)
  inner_shadow(x,y,w,h)
  core.rect(x, y, w, h, bg or core.theme.panelBg)
  core.frame(x,y,w,h, border or core.theme.border)
  if title and title~="" then core.text(x+2,y,"["..title.."]", core.theme.text) end
end

-- карточка игры: НИКАКОЙ синей рамки, скругления и маленькая тень
function core.card(x,y,w,h,title)
  inner_shadow(x,y,w,h)
  core.rect(x, y, w, h, core.theme.card)
  cut_corners(x,y,w,h, core.theme.card)
  if title and title~="" then core.text(x+2,y,"["..title.."]", core.theme.text) end
end

-- лог-панель справа
function core.logpane(x,y,w,h,lines)
  core.card_shadow(x,y,w,h, core.theme.panelBg, core.theme.border, nil)
  if not lines then return end
  local maxLines = h-2
  local start = math.max(1, #lines - maxLines + 1)
  local cy = y+1
  for i=start,#lines do
    local s=tostring(lines[i]); if #s>w-2 then s=s:sub(1,w-5).."..." end
    core.text(x+1, cy, s, core.theme.muted); cy = cy + 1
  end
end

-- кнопка: без обводки; скругления + внутренняя маленькая тень
local function inside(mx,my,b) return mx>=b.x and mx<=b.x+b.w-1 and my>=b.y and my<=b.y+b.h-1 end
function core.button(x,y,w,h,label,bg,fg,onClick)
  h = math.max(3, h or 3)
  label = label or "OK"; bg = bg or core.theme.primary; fg = fg or 0x000000

  -- маленькая внутренняя тень
  inner_shadow(x,y,w,h)

  -- тело
  core.rect(x, y, w, h, bg)
  cut_corners(x,y,w,h,bg)

  -- текст по центру с учётом Unicode
  local lbl = tostring(label)
  local ulen = unicode.len(lbl)
  local maxw = math.max(0, w-2)
  if ulen > maxw then
    -- обрезаем по символам, добавляя …
    local cut = maxw-1
    if cut < 0 then cut = 0 end
    lbl = unicode.sub(lbl, 1, cut) .. (maxw>0 and "…" or "")
    ulen = unicode.len(lbl)
  end
  local tx = x + math.floor((w - ulen)/2)
  local ty = y + math.floor((h-1)/2)
  core.text(tx, ty, lbl, fg)

  local b = {x=x,y=y,w=w,h=h,onClick=onClick}; table.insert(buttons,b); return b
end

function core.inBounds(ctrl,x,y) return ctrl and inside(x,y,ctrl) or false end
function core.dispatch_click(x,y)
  for _,b in ipairs(buttons) do if inside(x,y,b) then if b.onClick then pcall(b.onClick) end; return true end end
  return false
end

-- заголовок 4×5
local FONT4 = {
  ["A"]={" ## ","#  #","####","#  #","#  #"},
  ["E"]={"####","#   ","### ","#   ","####"},
  ["H"]={"#  #","#  #","####","#  #","#  #"},
  ["M"]={"#  #","## #","# ##","#  #","#  #"},
  ["O"]={" ## ","#  #","#  #","#  #"," ## "},
  ["R"]={"### ","#  #","### ","# # ","#  #"},
  ["S"]={" ###","#   "," ## ","   #","### "},
  ["T"]={"####","  # ","  # ","  # ","  # "},
  ["U"]={"#  #","#  #","#  #","#  #"," ## "},
}
local function drawBig4(x,y,ch,col)
  local pat = FONT4[ch] or {"####","####","####","####","####"}
  for r=1,5 do
    local row = pat[r]
    for c=1,#row do
      if row:sub(c,c) ~= " " then core.text(x+c-1, y+r-1, "█", col) end
    end
  end
end

function core.bigtitle_center(text, splitN, colLeft, colRight, y)
  text   = (text or "HAUSEMASTERS"):upper()
  splitN = splitN or 5
  local cw,gap = 4,1
  local totW   = #text*(cw+gap) - gap
  local scrW   = select(1, gpu.getResolution())
  local x0     = math.max(2, math.floor((scrW - totW)/2))
  local yy     = (y or 1)

  -- «щёчки» из двух ступеней
  core.rect(x0-10,     yy+2, 8, 1, core.theme.titleCheek)
  core.rect(x0-8,      yy+3, 6, 1, core.theme.titleCheek)
  core.rect(x0+totW+2, yy+2, 8, 1, core.theme.titleCheek)
  core.rect(x0+totW+2, yy+3, 6, 1, core.theme.titleCheek)

  for i=1,#text do
    local ch  = text:sub(i,i)
    local col = (i<=splitN) and (colLeft or core.theme.titleGray)
                             or (colRight or core.theme.titleYellow)
    drawBig4(x0 + (i-1)*(cw+gap), yy, ch, col)
  end
end

function core.shutdown()
  gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
  local w,h = gpu.getResolution(); gpu.fill(1,1,w,h," "); os.exit()
end

return core

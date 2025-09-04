-- /lib/ugui_core.lua — exact reactor-style

local gpu = require("component").gpu
local core = {}

-- палитра
core.theme = {
  -- фон окна и большие области
  bg            = 0x343434, -- очень тёмно-серый
  gridBg        = 0xB5B5B5, -- светло-серый внутри большого поля с играми
  gridEdgeDark  = 0x6A6A6A, -- внешний слой «толстой» рамки
  gridEdgeLight = 0x8E8E8E, -- внутренний слой «толстой» рамки

  -- карточки/панели/текст
  card     = 0x151719,      -- почти чёрные карточки игр
  panelBg  = 0x2E3033,      -- правые панели
  text     = 0xE8EBEF,
  muted    = 0xBFC4CA,

  -- акценты
  border   = 0x6D77FF,      -- тонкая синяя рамка для малых панелей
  primary  = 0x12D4C6,      -- бирюзовая кнопка
  danger   = 0xFF7C8F,      -- розово-красная

  -- тени/контуры
  shadow1  = 0x25272A,      -- мягкая 1px тень
  outline  = 0x0E0F11,

  -- заголовок
  titleGray   = 0xD0D0D0,
  titleYellow = 0xF0B915,
  titleCheek  = 0x8E8E8E,   -- серые «щёчки» под заголовком
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

-- базовые примитивы ---------------------------------------------
local function setfg(c) if c then gpu.setForeground(c) end end
local function setbg(c) if c then gpu.setBackground(c) end end

function core.text(x,y,s,fg) setfg(fg); gpu.set(x,y,s or "") end
function core.rect(x,y,w,h,bg,fg,char)
  setbg(bg); if fg then gpu.setForeground(fg) end
  for i=0,h-1 do gpu.fill(x, y+i, w, 1, char or " ") end
end

-- тонкая скруглённая рамка (для малых панелей/шкал)
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

-- ТОЛСТАЯ «квадратная» рамка под большую область игр (два слоя)
function core.big_grid_frame(x,y,w,h)
  -- внешний слой
  core.rect(x, y, w, h, core.theme.gridEdgeDark)
  -- внутренний слой
  core.rect(x+2, y+2, w-4, h-4, core.theme.gridEdgeLight)
  -- собственно светлый фон
  core.rect(x+4, y+4, w-8, h-8, core.theme.gridBg)
end

-- карточки и панели (без грязных теней — только 1px)
function core.card_shadow(x,y,w,h,bg,border,_,title)
  core.rect(x+1,y+1,w,h, core.theme.shadow1)           -- 1px тень
  core.rect(x,y,w,h, bg or core.theme.card)            -- тело
  core.frame(x,y,w,h, border or core.theme.border)     -- тонкая рамка
  if title and title~="" then core.text(x+2,y,"["..title.."]", core.theme.text) end
end
function core.card(x,y,w,h,title) core.card_shadow(x,y,w,h, core.theme.card, core.theme.border, nil, title) end
function core.logpane(x,y,w,h,lines)
  core.card_shadow(x,y,w,h, core.theme.panelBg, core.theme.border, nil)
  if not lines then return end
  local maxLines = h-2
  local start = math.max(1, #lines - maxLines + 1)
  local cy = y+1
  for i=start,#lines do
    local s = tostring(lines[i]); if #s>w-2 then s=s:sub(1,w-5).."..." end
    core.text(x+1, cy, s, core.theme.muted); cy = cy + 1
  end
end

-- крупные кнопки-«пилюли» (майнкрафт-скругления — срез пикселя)
local function inside(mx,my,b) return mx>=b.x and mx<=b.x+b.w-1 and my>=b.y and my<=b.y+b.h-1 end
function core.button(x,y,w,h,label,bg,fg,onClick)
  h = math.max(3, h or 3)
  label = label or "OK"; bg = bg or core.theme.primary; fg = fg or 0x000000

  core.rect(x+1, y+1, w, h, core.theme.shadow1)   -- 1px тень
  core.rect(x,   y,   w, h, bg)                   -- тело

  -- «пиксельное скругление»: глушим углы
  if w>=4 then
    setbg(bg)
    gpu.fill(x,     y,     1, 1, " ")
    gpu.fill(x+w-1, y,     1, 1, " ")
    gpu.fill(x,     y+h-1, 1, 1, " ")
    gpu.fill(x+w-1, y+h-1, 1, 1, " ")
  end
  core.frame(x, y, w, h, core.theme.outline)      -- тонкий контур

  local tx = x + math.floor((w - #label)/2)
  local ty = y + math.floor(h/2)
  core.text(tx, ty, label, fg)

  local b = {x=x,y=y,w=w,h=h,onClick=onClick}; table.insert(buttons,b); return b
end
function core.inBounds(ctrl,x,y) return ctrl and inside(x,y,ctrl) or false end
function core.dispatch_click(x,y)
  for _,b in ipairs(buttons) do if inside(x,y,b) then if b.onClick then pcall(b.onClick) end; return true end end
  return false
end

-- БОЛЬШОЙ «пиксельный» заголовок без подложки (HOUSE/MASTERS)
-- Мини-шрифт 5×5 для нужных букв
local FONT = {
  ["A"]={"  #  "," # # ","#####","#   #","#   #"},
  ["E"]={"#####","#    ","#### ","#    ","#####"},
  ["H"]={"#   #","#   #","#####","#   #","#   #"},
  ["M"]={"#   #","## ##","# # #","#   #","#   #"},
  ["O"]={" ### ","#   #","#   #","#   #"," ### "},
  ["R"]={"#### ","#   #","#### ","#  # ","#   #"},
  ["S"]={" ####","#    "," ### ","    #","#### "},
  ["T"]={"#####","  #  ","  #  ","  #  ","  #  "},
  ["U"]={"#   #","#   #","#   #","#   #"," ### "},
}
local function drawBigChar(x,y,ch,col)
  local pat = FONT[ch] or {"#####","#####","#####","#####","#####" }
  for r=1,5 do
    local row = pat[r]
    for c=1,#row do
      if row:sub(c,c) ~= " " then
        core.text(x+c-1, y+r-1, "█", col)
      end
    end
  end
end

function core.bigtitle_center(text, splitN, colLeft, colRight, y)
  text   = (text or "HOUSEMASTERS"):upper()
  splitN = splitN or 5
  local cw, gap = 5, 1
  local totW = #text*(cw+gap) - gap
  local scrW = select(1, gpu.getResolution())
  local x0   = math.max(2, math.floor((scrW - totW)/2))
  local yy   = (y or 1)

  -- серые «щёчки» под заголовком
  core.rect(x0-22, yy+3, 20, 1, core.theme.titleCheek)
  core.rect(x0-16, yy+4, 16, 1, core.theme.titleCheek)
  core.rect(x0+totW+2, yy+3, 20, 1, core.theme.titleCheek)
  core.rect(x0+totW+2, yy+4, 16, 1, core.theme.titleCheek)

  for i=1,#text do
    local ch = text:sub(i,i)
    local col = (i<=splitN) and (colLeft or core.theme.titleGray) or (colRight or core.theme.titleYellow)
    drawBigChar(x0 + (i-1)*(cw+gap), yy, ch, col)
  end
end

function core.shutdown()
  gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
  local w,h = gpu.getResolution(); gpu.fill(1,1,w,h," "); os.exit()
end

return core

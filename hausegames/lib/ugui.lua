-- /lib/ugui.lua — адаптер к новому рендеру на базе ugui_core.lua
-- сохраняет старый API (&-цвета, drawMain, drawFrame) +
-- прокидывает расширенные виджеты из ugui_core.

local Core = require("ugui_core")
local gpu      = require("component").gpu
local unicode  = require("unicode")

local M = {}

-- палитра для &0..&f (как в старом ugui)
local palette = {
  ["0"]=0x000000, ["1"]=0x0000AA, ["2"]=0x00AA00, ["3"]=0x00AAAA,
  ["4"]=0xAA0000, ["5"]=0xAA00AA, ["6"]=0xFFAA00, ["7"]=0xAAAAAA,
  ["8"]=0x555555, ["9"]=0x5555FF, ["a"]=0x55FF55, ["b"]=0x55FFFF,
  ["c"]=0xFF5555, ["d"]=0xFF55FF, ["e"]=0xFFFF55, ["f"]=0xFFFFFF,
}

-- ВАЖНО: совместимость со старым кодом
-- craft_gui.lua читает gui.colors.border и т.п.
M.colors = {
  border  = "9",  -- синий контур (как раньше)
  text    = "f",
  dim     = "7",
  primary = "b",
  danger  = "c",
  warn    = "e",
  ok      = "a",
  shadow  = "0",
  card    = "8",
}
-- чтобы при желании можно было брать rgb по коду
M.palette = palette

-- тема из Core
M.theme = Core.theme

----------------------------------------------------------------
-- 1) Совместимые функции со старым ugui.lua
----------------------------------------------------------------

-- печать строки с &-цветами через буфер Core
function M.text(x, y, str)
  if not str or str == "" then return end
  local curColor = M.theme.text
  local i, cx = 1, x
  while i <= #str do
    local ch = str:sub(i,i)
    if ch == "&" and i < #str then
      local c = str:sub(i+1,i+1)
      curColor = palette[c] or curColor
      i = i + 2
    else
      -- unicode-safe: один символ
      local uch = unicode.sub(str, unicode.len(str:sub(1,i-1))+1, unicode.len(str:sub(1,i-1))+1)
      Core.text(cx, y, uch, curColor)
      cx = cx + 1
      i = i + 1
    end
  end
end

-- верхняя линия + заголовок
function M.drawMain(title, borderCode, bgCode)
  local w = select(1, gpu.getResolution())
  local border = palette[borderCode or M.colors.border] or 0x777777
  Core.text(1, 1, string.rep("─", w), border)
  if title and title ~= "" then
    M.text(2, 1, title)
  end
end

-- рамка с легким фоном и заголовком в [ ]
function M.drawFrame(x, y, w, h, title, borderCode)
  local col = palette[borderCode or M.colors.border] or 0x777777
  Core.rect(x, y, w, h, M.theme.card)
  Core.frame(x, y, w, h, col)
  if title and title ~= "" then
    M.text(x+2, y, "["..title.."]")
  end
end

----------------------------------------------------------------
-- 2) Делегирование в Core (расширенный API)
----------------------------------------------------------------
function M.clear(bg)                     Core.clear(bg or M.theme.bg) end
function M.flush()                       Core.flush() end
function M.rect(x,y,w,h,bg,fg,char)     Core.rect(x,y,w,h,bg,fg,char) end
function M.frame(x,y,w,h,col)            Core.frame(x,y,w,h,col) end
function M.card(x,y,w,h,title)           Core.card(x,y,w,h,title) end
function M.button(x,y,w,h,label,opts)
  opts = opts or {}
  local b = Core.button(
    x,y,w,h,
    label or "OK",
    opts.bg or M.theme.primary,
    opts.fg or 0x000000
  )
  b.id = opts.id
  return b
end
function M.vbar(x,y,h,value,min,max,col,back)
  Core.vbar(x,y,h,value,min,max,col,back)
end
function M.log(x,y,w,h,lines) Core.logpane(x,y,w,h, lines or {}) end
function M.inBounds(ctrl, cx, cy) return Core.inBounds(ctrl, cx, cy) end

return M

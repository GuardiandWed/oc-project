-- /lib/ugui.lua — адаптер к новому рендеру на базе ugui_core.lua
-- сохраняет твой API (&-цвета в text, drawMain, drawFrame),
-- + даёт доступ к расширенным виджетам Core.

local Core     = require("lib.ugui_core")
local gpu      = require("component").gpu
local unicode  = require("unicode")

local M = {}

-- палитра для &0..&f (как в твоём старом ugui)
local palette = {
  ["0"]=0x000000, ["1"]=0x0000AA, ["2"]=0x00AA00, ["3"]=0x00AAAA,
  ["4"]=0xAA0000, ["5"]=0xAA00AA, ["6"]=0xFFAA00, ["7"]=0xAAAAAA,
  ["8"]=0x555555, ["9"]=0x5555FF, ["a"]=0x55FF55, ["b"]=0x55FFFF,
  ["c"]=0xFF5555, ["d"]=0xFF55FF, ["e"]=0xFFFF55, ["f"]=0xFFFFFF,
}

-- прокинем тему наружу
M.theme = Core.theme

----------------------------------------------------------------
-- 1) Совместимые функции с твоего старого ugui.lua
----------------------------------------------------------------

-- печать строки с &-цветами через буфер Core (без прямых gpu.set)
function M.text(x, y, str)
  if not str or str == "" then return end
  local cx = x
  local curColor = M.theme.text
  local i = 1
  while i <= #str do
    local ch = str:sub(i,i)
    if ch == "&" and i < #str then
      local c = str:sub(i+1,i+1)
      curColor = palette[c] or curColor
      i = i + 2
    else
      -- печатаем посимвольно (unicode-safe)
      local uch = unicode.sub(str, unicode.len(str:sub(1,i-1))+1, unicode.len(str:sub(1,i-1))+1)
      Core.text(cx, y, uch, curColor)
      cx = cx + 1
      i = i + 1
    end
  end
end

-- простая шапка (линия и заголовок)
function M.drawMain(title, borderCode, bgCode)
  local w, h = gpu.getResolution()
  local border = palette[borderCode or "9"] or 0x777777
  -- линия сверху
  Core.text(1, 1, string.rep("─", w), border)
  -- заголовок
  if title and title ~= "" then
    M.text(2, 1, title)
  end
end

-- рамка box-drawing + заголовок в [ ]
function M.drawFrame(x, y, w, h, title, borderCode)
  local col = palette[borderCode or "9"] or 0x777777
  -- фон внутри рамки лёгкий
  Core.rect(x, y, w, h, M.theme.card)
  Core.frame(x, y, w, h, col)
  if title and title ~= "" then
    local cap = "["..title.."]"
    M.text(x+2, y, cap)
  end
end

----------------------------------------------------------------
-- 2) Расширенный API (делегирование в Core) — можно использовать в новом коде
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
-- вертикальный индикатор/прогресс-бар
function M.vbar(x,y,h,value,min,max,col,back)
  Core.vbar(x,y,h,value,min,max,col,back)
end
-- лог-панель
function M.log(x,y,w,h,lines) Core.logpane(x,y,w,h, lines or {}) end
-- хит-тест
function M.inBounds(ctrl, cx, cy) return Core.inBounds(ctrl, cx, cy) end

return M

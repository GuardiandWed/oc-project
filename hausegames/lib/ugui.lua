-- /lib/ugui.lua — адаптер &-цветов + баннер и панели

local Core     = require("ugui_core")
local unicode  = require("unicode")

local M = {}

local palette = {
  ["0"]=0x000000, ["1"]=0x0000AA, ["2"]=0x00AA00, ["3"]=0x00AAAA,
  ["4"]=0xAA0000, ["5"]=0xAA00AA, ["6"]=0xFFAA00, ["7"]=0xAAAAAA,
  ["8"]=0x555555, ["9"]=0x5555FF, ["a"]=0x55FF55, ["b"]=0x55FFFF,
  ["c"]=0xFF5555, ["d"]=0xFF55FF, ["e"]=0xFFFF55, ["f"]=0xFFFFFF,
}

M.colors = { border="9", text="f", dim="7", primary="b", danger="c" }
M.palette = palette
M.theme   = Core.theme

-- печать с &-цветами
function M.text(x,y,str)
  if not str or str=="" then return end
  local ulen = unicode.len(str)
  local cx, i = x, 1
  local cur = M.theme.text
  while i <= ulen do
    local ch = unicode.sub(str,i,i)
    if ch=="&" and i<ulen then
      local c = unicode.sub(str,i+1,i+1); cur = palette[c] or cur; i=i+2
    else
      Core.text(cx,y,ch,cur); cx=cx+1; i=i+1
    end
  end
end

function M.drawMain(title) Core.banner_center(title or "HAUSEGAMES") end
function M.drawFrame(x,y,w,h,title) Core.card_shadow(x,y,w,h, Core.theme.panelBg, Core.theme.border, Core.theme.shadow2, title) end

-- делегаты
function M.clear(bg)                     Core.clear(bg or Core.theme.bg) end
function M.flush()                       Core.flush() end
function M.rect(x,y,w,h,bg,fg,char)     Core.rect(x,y,w,h,bg,fg,char) end
function M.frame(x,y,w,h,col)            Core.frame(x,y,w,h,col) end
function M.card(x,y,w,h,title)           Core.card(x,y,w,h,title) end
function M.vbar(x,y,h,value,min,max,col,back) Core.vbar(x,y,h,value,min,max,col,back) end
function M.log(x,y,w,h,lines)            Core.logpane(x,y,w,h, lines or {}) end
function M.inBounds(ctrl, cx, cy)        return Core.inBounds(ctrl, cx, cy) end
function M.button(x,y,w,h,label,opts)
  opts = opts or {}
  return Core.button(x,y,w,h, label or "OK", opts.bg or Core.theme.primary, opts.fg or 0x000000, opts.onClick)
end

return M

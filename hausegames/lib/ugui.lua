-- /lib/ugui.lua — &-цвета + обёртки для большого фрейма и заголовка

local Core    = require("ugui_core")
local unicode = require("unicode")

local M = {}
local palette = {
  ["0"]=0x000000, ["1"]=0x0000AA, ["2"]=0x00AA00, ["3"]=0x00AAAA,
  ["4"]=0xAA0000, ["5"]=0xAA00AA, ["6"]=0xFFAA00, ["7"]=0xAAAAAA,
  ["8"]=0x555555, ["9"]=0x6D77FF, ["a"]=0x55FF55, ["b"]=0x12D4C6,
  ["c"]=0xFF7C8F, ["d"]=0xFF55FF, ["e"]=0xF0B915, ["f"]=0xFFFFFF,
}
M.theme = Core.theme
M.palette = palette

local function put_colored(x,y,str)
  local ulen = unicode.len(str); local cx,i,cur = x,1,M.theme.text
  while i<=ulen do
    local ch = unicode.sub(str,i,i)
    if ch=="&" and i<ulen then local c=unicode.sub(str,i+1,i+1); cur=palette[c] or cur; i=i+2
    else Core.text(cx,y,ch,cur); cx=cx+1; i=i+1 end
  end
end

function M.text(x,y,str) if str and str~="" then put_colored(x,y,str) end end
function M.drawMain(titleLeftGrayCount)
  -- HOUSEMASTERS: первые 5 букв серые, остальные жёлтые
  Core.bigtitle_center("HOUSEMASTERS", titleLeftGrayCount or 5, M.theme.titleGray, M.theme.titleYellow, 1)
end
function M.bigGrid(x,y,w,h) Core.big_grid_frame(x,y,w,h) end
function M.drawFrame(x,y,w,h,title) Core.card_shadow(x,y,w,h, Core.theme.panelBg, Core.theme.border, nil, title) end

-- делегаты
function M.clear(bg) Core.clear(bg or Core.theme.bg) end
function M.flush() Core.flush() end
function M.card(x,y,w,h,title) Core.card(x,y,w,h,title) end
function M.button(x,y,w,h,label,opts)
  opts=opts or {}; return Core.button(x,y,w,h, label or "OK", opts.bg or Core.theme.primary, opts.fg or 0x000000, opts.onClick)
end
function M.log(x,y,w,h,lines) Core.logpane(x,y,w,h, lines or {}) end
function M.inBounds(ctrl, cx, cy) return Core.inBounds(ctrl, cx, cy) end
return M

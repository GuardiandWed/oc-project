-- ugui.lua — минимальный GUI-слой с &-цветами и рамками
local component = require("component")
local gpu = component.gpu
local unicode = require("unicode")

local M = {}

-- палитра под &0..&f (похожа на minecraft)
local palette = {
  ["0"]=0x000000, ["1"]=0x0000AA, ["2"]=0x00AA00, ["3"]=0x00AAAA,
  ["4"]=0xAA0000, ["5"]=0xAA00AA, ["6"]=0xFFAA00, ["7"]=0xAAAAAA,
  ["8"]=0x555555, ["9"]=0x5555FF, ["a"]=0x55FF55, ["b"]=0x55FFFF,
  ["c"]=0xFF5555, ["d"]=0xFF55FF, ["e"]=0xFFFF55, ["f"]=0xFFFFFF,
}

M.colors = {
  border = "9", -- просто используем как код для цвета рамки
}

local function setColorByCode(code)
  local col = palette[code]
  if col then pcall(gpu.setForeground, col) end
end

-- печать строки с &-кодами
function M.text(x, y, str)
  if not str then return end
  local old = { gpu.getForeground() }
  local i = 1
  local cx = x
  while i <= #str do
    local ch = str:sub(i,i)
    if ch == "&" and i < #str then
      local c = str:sub(i+1,i+1)
      setColorByCode(c)
      i = i + 2
    else
      gpu.set(cx, y, ch)
      cx = cx + 1
      i = i + 1
    end
  end
  pcall(gpu.setForeground, old[1])
end

-- простая шапка
function M.drawMain(title, borderCode, bgCode)
  local w,h = gpu.getResolution()
  local oldF, oldB = gpu.getForeground(), gpu.getBackground()
  setColorByCode(borderCode or "9")
  for x=1,w do gpu.set(x,1,"─") end
  M.text(2,1,title or "")
  pcall(gpu.setForeground, oldF); pcall(gpu.setBackground, oldB)
end

-- рамка box-drawing + заголовок в [ ]
function M.drawFrame(x,y,w,h,title,borderCode)
  local oldF = gpu.getForeground()
  setColorByCode(borderCode or "9")
  gpu.set(x, y, "┌"..string.rep("─", w-2).."┐")
  for i=1,h-2 do gpu.set(x, y+i, "│"..string.rep(" ", w-2).."│") end
  gpu.set(x, y+h-1, "└"..string.rep("─", w-2).."┘")
  if title and title ~= "" then
    local cap = "["..title.."]"
    M.text(x+2, y, cap)
  end
  pcall(gpu.setForeground, oldF)
end

return M

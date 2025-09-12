-- /lib/doubleBuffering.lua — простой shim на gpu
local gpu = require("component").gpu
local M = {}
function M.setResolution(w,h) if w and h then gpu.setResolution(w,h) end end
function M.clear(color) local old=gpu.getBackground(); if color then gpu.setBackground(color) end
  local W,H=gpu.getResolution(); gpu.fill(1,1,W,H," "); gpu.setBackground(old) end
function M.drawText(x,y,color,str) local of=gpu.getForeground(); if color then gpu.setForeground(color) end
  gpu.set(x,y,str or ""); if color then gpu.setForeground(of) end end
function M.drawRectangle(x,y,w,h,color,_,ch) local ob=gpu.getBackground(); if color then gpu.setBackground(color) end
  for i=0,(h or 1)-1 do gpu.fill(x,y+i,w or 1,1,ch or " ") end; gpu.setBackground(ob) end
function M.drawImage() end
function M.drawChanges() end
function M.copy() end
function M.paste() end
return M

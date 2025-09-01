-- /home/craft_gui.lua
local gui     = require("sgui")
local gpu     = require("component").gpu
local unicode = require("unicode")

local G = {}

-- геометрия
G.bounds       = { x = 2,  y = 2,  w = 116, h = 36 }
G.listBounds   = { x = 4,  y = 10, w = 70,  h = 21 }
G.infoBounds   = { x = 76, y = 7,  w = 40,  h = 24 }
G.searchBounds = { x = 4,  y = 4,  w = 50,  h = 1  }
G.filtersY     = 7

-- состояние
G.searchText   = ""
G.craftables   = {}
G.rowMap       = {}
G.focusSearch  = false

G.filters = { onlyCraftable=false, onlyStored=false, exact=false }

-- модовый фильтр
G.modFilter = { selected={}, includeOther=false, all=true, topMods={} }

-- верхние кнопки
G.btnStop  = { x = 116-8,  y = 2, w=8,  h=1, label = "[Стоп]" }
G.btnJobs  = { x = 116-18, y = 2, w=10, h=1, label = "[Задания]" }

-- модалки
G.dialog     = { visible=false, item=nil, qty="1", okBtn=nil, cancelBtn=nil, inputBox=nil }
G.jobsDialog = { visible=false, jobs={}, closeBtn=nil, cancelHotspots={} }
G.modsDialog = { visible=false, items={}, applyBtn=nil, cancelBtn=nil, toggleMap={} }

-- ===== helpers =====
local function clearRect(x,y,w,h) for i=0,h-1 do gui.text(x, y+i, string.rep(" ", w)) end end
local function centerBox(W,H) local sw,sh=gpu.getResolution(); return math.floor((sw-W)/2), math.floor((sh-H)/2) end
local function pointIn(tx,ty,r) return r and tx>=r.x and ty>=r.y and tx<=r.x+r.w-1 and ty<=r.y+r.h-1 end
local function stripAmp(s) return

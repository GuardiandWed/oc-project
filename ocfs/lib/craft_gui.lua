-- craft_gui.lua — GUI на базе ugui
local gui     = require("ugui")
local gpu     = require("component").gpu
local unicode = require("unicode")

local G = {}

-- геометрия
G.bounds       = { x=2,  y=2,  w=116, h=36 }
G.listBounds   = { x=4,  y=10, w=70,  h=21 }
G.infoBounds   = { x=76, y=7,  w=40,  h=24 }
G.searchBounds = { x=4,  y=4,  w=50,  h=1  }
G.filtersY     = 7
G.statusY      = 38

-- состояние
G.searchText    = ""
G.craftables    = {}
G.rowMap        = {}
G.focusSearch   = false
G.selectedIndex = nil

-- верхние кнопки
G.btnJobs  = { x=98, y=2, w=10, h=1, label="&b[Задания]" }
G.btnStop  = { x=108,y=2, w=8,  h=1, label="&c[Стоп]" }

-- фильтр модов
G.modFilter = {
  all         = false,
  includeOther= false,
  selected    = {},    -- modid => true
  topMods     = {},    -- массив modid для диалога
}

-- диалоги
G.dialog     = { visible=false, item=nil, qty="1", okBtn=nil, cancelBtn=nil, inputBox=nil }
G.jobsDialog = { visible=false, jobs={}, closeBtn=nil, items={} }
G.modsDialog = { visible=false, items={}, applyBtn=nil, cancelBtn=nil, map={}, otherBtn=nil, allBtn=nil }

local function clear(x,y,w,h) for i=0,h-1 do gui.text(x, y+i, string.rep(" ", w)) end end
local function center(W,H) local sw,sh=gpu.getResolution(); return math.floor((sw-W)/2), math.floor((sh-H)/2) end
local function inside(tx,ty,r) return r and tx>=r.x and ty>=r.y and tx<=r.x+r.w-1 and ty<=r.y+r.h-1 end

local function modFilterCaption()
  if G.modFilter.all then return "Все" end
  local n=0; for _ in pairs(G.modFilter.selected) do n=n+1 end
  if n==0 and not G.modFilter.includeOther then return "MMCE" end
  if n==0 and G.modFilter.includeOther then return "Остальное" end
  return ("Выбрано: "..n..(G.modFilter.includeOther and "+другое" or ""))
end

function G.draw_shell(title)
  gui.drawMain(title or "&d[Крафты ME]", gui.colors.border, "2")
  gui.drawFrame(G.bounds.x, G.bounds.y, G.bounds.w, G.bounds.h, "Панель крафта", gui.colors.border)

  -- верхние кнопки
  gui.text(G.btnJobs.x, G.btnJobs.y, G.btnJobs.label)
  gui.text(G.btnStop.x, G.btnStop.y, G.btnStop.label)

  -- поиск
  gui.text(G.searchBounds.x, G.searchBounds.y, "&7Поиск: ")
  clear(G.searchBounds.x+8, G.searchBounds.y, G.searchBounds.w-8, 1)
  local caret = G.focusSearch and "&f▌" or ""
  local shown = G.searchText
  if unicode.len(shown) > (G.searchBounds.w-10) then
    shown = unicode.sub(shown, 1, G.searchBounds.w-13).."..."
  end
  gui.text(G.searchBounds.x+8, G.searchBounds.y, "&f"..shown..caret)

  -- фильтр модов
  local cap = modFilterCaption()
  local fx = G.searchBounds.x + G.searchBounds.w + 2
  gui.text(fx, G.searchBounds.y, "&8[Фильтр: &b"..cap.."&8]")
  G.filterBtn = { x=fx, y=G.searchBounds.y, w=15+#cap, h=1 }

  -- рамки
  gui.drawFrame(G.listBounds.x-2,  G.listBounds.y-2,  G.listBounds.w+4,  G.listBounds.h+4,  "Доступно к крафту", gui.colors.border)
  gui.drawFrame(G.infoBounds.x-2,  G.infoBounds.y-2,  G.infoBounds.w+4,  G.infoBounds.h+4,  "Информация",        gui.colors.border)

  -- очистка зон
  clear(G.listBounds.x, G.listBounds.y, G.listBounds.w, G.listBounds.h+1)
  clear(G.infoBounds.x, G.infoBounds.y, G.infoBounds.w, G.infoBounds.h)
end

function G.render_list()
  local x,y,w,h = G.listBounds.x, G.listBounds.y, G.listBounds.w, G.listBounds.h
  clear(x,y,w,h); G.rowMap={}
  local shown = math.min(#G.craftables, h)
  for i=1,shown do
    local line = G.craftables[i].label or "<?>"
    if unicode.len(line) > w-2 then line = unicode.sub(line,1,w-5).."..."
    end
    local prefix = (G.selectedIndex==i) and "&a> " or "  "
    gui.text(x, y+i-1, prefix.."&f"..line)
    G.rowMap[y+i-1] = i
  end
  clear(x, y+h, w, 1)
  gui.text(x, y+h, string.format("&7Найдено: &b%d", #G.craftables))
end

function G.render_info(item, info)
  local x,y,w,h = G.infoBounds.x, G.infoBounds.y, G.infoBounds.w, G.infoBounds.h
  clear(x,y,w,h)
  if not item then gui.text(x,y,"&7Выберите предмет."); return end
  gui.text(x, y,   "&fПредмет: &b"..(item.label or "<?>"))
  gui.text(x, y+2, "&7ID: &8"..tostring(item.name or "<?>"))
  gui.text(x, y+3, "&7Mod: &8"..tostring(item.mod or "?"))
  if info and info.ok then
    gui.text(x, y+5, "&7В сети: &b"..tostring(info.inNetwork or 0))
    gui.text(x, y+6, "&7Крафтабельно: "..(info.craftable and "&aДа" or "&cНет"))
  end
end

function G.render_status(cpu)
  clear(2, G.statusY, 116, 1)
  if cpu then gui.text(4, G.statusY, string.format("&7CPU: &b%d&7, занято: &c%d", cpu.total or 0, cpu.busy or 0))
  else gui.text(4, G.statusY, "&7CPU: &8н/д") end
end

-- ===== модалка крафта =====
function G.open_dialog(row) G.dialog.visible=true; G.dialog.item=row; G.dialog.qty="1" end
function G.close_dialog() G.dialog.visible=false; G.dialog.item=nil end
function G.render_dialog()
  if not (G.dialog.visible and G.dialog.item) then return end
  local W,H = 48,10
  local x,y = center(W,H)
  gui.drawFrame(x,y,W,H,"Запуск крафта", gui.colors.border)
  gui.text(x+2, y+2, "&fПредмет: &b"..(G.dialog.item.label or "<?>"))

  G.dialog.inputBox = {x=x+2, y=y+4, w=12, h=1}
  clear(G.dialog.inputBox.x, G.dialog.inputBox.y, G.dialog.inputBox.w, 1)
  gui.text(G.dialog.inputBox.x, G.dialog.inputBox.y, "&f"..(G.dialog.qty or "1"))

  local by=y+H-3
  G.dialog.okBtn     = {x=x+W-24, y=by, w=10, h=1}
  G.dialog.cancelBtn = {x=x+W-12, y=by, w=10, h=1}
  gui.text(G.dialog.okBtn.x,     by, "&a[Запуск]")
  gui.text(G.dialog.cancelBtn.x, by, "&c[Отмена]")
end

-- ===== модалка заданий =====
function G.open_jobs_dialog(jobs) G.jobsDialog.visible=true; G.jobsDialog.jobs=jobs or {} end
function G.close_jobs_dialog() G.jobsDialog.visible=false; G.jobsDialog.jobs={} end
function G.render_jobs_dialog()
  if not G.jobsDialog.visible then return end
  local W,H = 90, 14
  local x,y = center(W,H)
  gui.drawFrame(x,y,W,H,"Активные задания", gui.colors.border)
  G.jobsDialog.closeBtn = { x=x+W-12, y=y, w=10, h=1 }
  gui.text(G.jobsDialog.closeBtn.x, y, "&c[Закрыть]")

  G.jobsDialog.items={}
  if not G.jobsDialog.jobs or #G.jobsDialog.jobs==0 then
    gui.text(x+2, y+3, "&7Нет активных заданий или функция недоступна.")
    return
  end
  for i=1, math.min(#G.jobsDialog.jobs, H-4) do
    local job = G.jobsDialog.jobs[i]
    local id  = job.id or job.ID or i
    local what= job.item or job.what or "craft"
    gui.text(x+2, y+1+i, string.format("&f#%s &7— &b%s", tostring(id), tostring(what)))
    local btn = {x=x+W-20, y=y+1+i, w=12, h=1, id=id}
    gui.text(btn.x, btn.y, "&c[Отменить]")
    table.insert(G.jobsDialog.items, btn)
  end
end

-- ===== модалка модов =====
function G.open_mods_dialog(mods, selected, includeOther, all)
  G.modsDialog.visible=true
  G.modsDialog.items = mods or {}
  G.modsDialog.map   = {}
  for _,mid in ipairs(G.modsDialog.items) do
    G.modsDialog.map[mid] = selected and selected[mid] or false
  end
  G.modsDialog.includeOther = includeOther or false
  G.modsDialog.all          = all or false
end
function G.close_mods_dialog() G.modsDialog.visible=false end
function G.render_mods_dialog()
  if not G.modsDialog.visible then return end
  local W,H = 60, 18
  local x,y = center(W,H)
  gui.drawFrame(x,y,W,H,"Фильтр модов", gui.colors.border)

  local listY = y+2
  local show = math.min(#G.modsDialog.items, H-6)
  for i=1,show do
    local mid = G.modsDialog.items[i]
    local mark = G.modsDialog.map[mid] and "&a[✔]" or "&7[ ]"
    gui.text(x+2, listY+i-1, mark.." &f"..mid)
  end

  G.modsDialog.otherBtn = {x=x+2,  y=y+H-5, w=14, h=1}
  G.modsDialog.allBtn   = {x=x+18, y=y+H-5, w=10, h=1}
  gui.text(G.modsDialog.otherBtn.x, G.modsDialog.otherBtn.y, (G.modsDialog.includeOther and "&a[✔]" or "&7[ ]").." &fОстальное")
  gui.text(G.modsDialog.allBtn.x,   G.modsDialog.allBtn.y,   (G.modsDialog.all and "&a[✔]" or "&7[ ]").." &fВсе")

  G.modsDialog.applyBtn  = {x=x+W-24, y=y+H-3, w=10, h=1}
  G.modsDialog.cancelBtn = {x=x+W-12, y=y+H-3, w=10, h=1}
  gui.text(G.modsDialog.applyBtn.x,  G.modsDialog.applyBtn.y,  "&a[Применить]")
  gui.text(G.modsDialog.cancelBtn.x, G.modsDialog.cancelBtn.y, "&c[Отмена]")
end

-- ===== обработчики =====
function G.handle_touch(screen, tx, ty)
  -- окна
  if G.jobsDialog.visible then
    if inside(tx,ty,G.jobsDialog.closeBtn) then G.close_jobs_dialog(); return "jobs_close" end
    for _,b in ipairs(G.jobsDialog.items or {}) do
      if inside(tx,ty,b) then return "jobs_cancel", b.id end
    end
    G.close_jobs_dialog(); return "jobs_close"
  end
  if G.modsDialog.visible then
    local W,H = 60,18; local x,y = center(W,H)
    local listY=y+2; local show=math.min(#G.modsDialog.items, H-6)
    for i=1,show do
      local ry=listY+i-1
      if tx>=x+2 and tx<=x+W-4 and ty==ry then
        local mid = G.modsDialog.items[i]
        G.modsDialog.map[mid] = not G.modsDialog.map[mid]
        return "mods_toggle"
      end
    end
    if inside(tx,ty,G.modsDialog.otherBtn) then
      G.modsDialog.includeOther = not G.modsDialog.includeOther; return "mods_toggle"
    elseif inside(tx,ty,G.modsDialog.allBtn) then
      G.modsDialog.all = not G.modsDialog.all; return "mods_toggle"
    elseif inside(tx,ty,G.modsDialog.applyBtn) then
      G.modFilter.selected = {}
      for mid,v in pairs(G.modsDialog.map) do if v then G.modFilter.selected[mid]=true end end
      G.modFilter.includeOther = G.modsDialog.includeOther
      G.modFilter.all          = G.modsDialog.all
      G.close_mods_dialog(); return "mods_apply"
    elseif inside(tx,ty,G.modsDialog.cancelBtn) then
      G.close_mods_dialog(); return "mods_cancel"
    else
      G.close_mods_dialog(); return "mods_cancel"
    end
  end
  if G.dialog.visible then
    if inside(tx,ty,G.dialog.okBtn) then return "dialog_ok"
    elseif inside(tx,ty,G.dialog.cancelBtn) then G.close_dialog(); return "dialog_cancel"
    elseif inside(tx,ty,G.dialog.inputBox) then return "dialog_focus_input"
    else G.close_dialog(); return "dialog_close" end
  end

  -- верх
  if inside(tx,ty,G.btnJobs) then return "open_jobs" end
  if inside(tx,ty,G.btnStop) then return "stop_all" end

  -- поиск
  local rect = {x=G.searchBounds.x+8, y=G.searchBounds.y, w=G.searchBounds.w-8, h=1}
  if inside(tx,ty,rect) then G.focusSearch=true; return "focus_search" else G.focusSearch=false end

  if inside(tx,ty,G.filterBtn) then return "open_mods" end

  -- список
  if tx>=G.listBounds.x and tx < G.listBounds.x+G.listBounds.w and
     ty>=G.listBounds.y and ty < G.listBounds.y+G.listBounds.h then
    local idx = G.rowMap[ty]
    if idx and G.craftables[idx] then
      G.selectedIndex = idx
      G.open_dialog(G.craftables[idx])
      return "open_dialog"
    end
  end
  return nil
end

function G.handle_key_down(ch, code)
  if G.dialog.visible then
    if ch and ch>=48 and ch<=57 then
      local cur = G.dialog.qty or "1"
      if cur=="1" then cur="" end
      if #cur<9 then G.dialog.qty = cur..string.char(ch) end
      return "dialog_qty_change"
    elseif code==14 then
      if #G.dialog.qty>1 then G.dialog.qty=G.dialog.qty:sub(1,-2) else G.dialog.qty="1" end
      return "dialog_qty_change"
    elseif code==28 then return "dialog_ok"
    elseif code==1 then G.close_dialog(); return "dialog_cancel" end
    return nil
  end
  if G.focusSearch then
    if ch and ch>=32 then
      G.searchText = G.searchText..string.char(ch); return "search_change"
    elseif code==14 then
      if #G.searchText>0 then G.searchText = G.searchText:sub(1,-2); return "search_change" end
    elseif code==28 then return "search_submit"
    elseif code==1 then G.focusSearch=false; return "search_blur" end
  end
  return nil
end

return G

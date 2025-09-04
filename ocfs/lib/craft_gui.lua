-- /home/craft_gui.lua
local gui     = require("ugui")
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
G.listPage     = 1

-- моды
G.allMods = {}

-- фильтр по модам
G.modFilter = { selected = {}, all = false }
G.modsDialog = {
  visible=false, page = 1, perPage = 14,
  items = {}, toggleMap = {},
  btnPrev=nil, btnNext=nil, applyBtn=nil, cancelBtn=nil
}

-- верхние кнопки
G.btnStop  = { x = 116-8,  y = 2, w=8,  h=1, label = "[Стоп]" }
G.btnJobs  = { x = 116-18, y = 2, w=10, h=1, label = "[Задания]" }
-- нижняя кнопка
G.btnReload = { x = 4, y = G.bounds.y + G.bounds.h + 1, w = 14, h = 1, label = "&b[Обновить кеш]" }

-- модалка крафта
G.dialog     = { visible=false, item=nil, qty="1", okBtn=nil, cancelBtn=nil, inputBox=nil }
-- модалка заданий
G.jobsDialog = { visible=false, jobs={}, closeBtn=nil, cancelHotspots={} }

-- ===== helpers =====
local function clearRect(x,y,w,h)
  for i=0,h-1 do gui.text(x, y+i, string.rep(" ", w)) end
end
local function getCenter(W,H)
  local sw, sh = gpu.getResolution()
  local x = math.floor((sw - W)/2)
  local y = math.floor((sh - H)/2)
  return x, y
end
local function pointIn(tx,ty,r)
  return r and tx >= r.x and ty >= r.y and tx <= r.x + r.w - 1 and ty <= r.y + r.h - 1
end
local function stripAmp(s) return (tostring(s or ""):gsub("&.", "")) end
local function textWidth(s) return unicode.len(stripAmp(s)) end
local function ucut(s, max) if unicode.len(s) <= max then return s end return unicode.sub(s,1,math.max(0,max-3)).."..." end

-- API для main.lua
function G.set_mods(list)
  G.allMods = list or {}
  table.sort(G.allMods)
  G.modFilter.selected = {}
  G.modFilter.all = false
  G.modsDialog.page = 1
end
function G.get_selected_mods_set()
  if G.modFilter.all then return nil end
  local s = G.modFilter.selected or {}
  for _,__ in pairs(s) do return s end
  return {}
end
function G.reset_list_page() G.listPage = 1 end

-- ===== каркас =====
function G.draw_shell(title)
  gui.drawMain(title or "&d[Крафты ME]", gui.colors["border"], "2")
  gui.drawFrame(G.bounds.x, G.bounds.y, G.bounds.w, G.bounds.h, "Панель крафта", gui.colors["border"])

  local jlbl, slbl = "&b"..G.btnJobs.label, "&c"..G.btnStop.label
  gui.text(G.btnJobs.x, G.btnJobs.y, jlbl)
  gui.text(G.btnStop.x, G.btnStop.y, slbl)
  G.btnJobs.w = textWidth(jlbl)
  G.btnStop.w = textWidth(slbl)

  gui.text(G.searchBounds.x, G.searchBounds.y, "&7Поиск: ")
  clearRect(G.searchBounds.x + 8, G.searchBounds.y, G.searchBounds.w - 8, 1)
  local caret = G.focusSearch and "&f▌" or ""
  local shown = G.searchText
  local maxChars = G.searchBounds.w - 10
  shown = ucut(shown, maxChars)
  gui.text(G.searchBounds.x + 8, G.searchBounds.y, "&f" .. shown .. caret)

  clearRect(4, G.filtersY, 70, 1)
  local selectedList = {}
  if not G.modFilter.all then
    for _,m in ipairs(G.allMods or {}) do
      if G.modFilter.selected[m] then selectedList[#selectedList+1] = m end
    end
  end
  local modSummary
  if G.modFilter.all then
    modSummary = "Все"
  else
    local n = #selectedList
    if n == 0 then modSummary = "—"
    elseif n <= 2 then modSummary = table.concat(selectedList, ", ")
    else modSummary = ("Выбрано: %d"):format(n) end
  end
  local modLabel = "&e[Моды: "..modSummary.."]"
  gui.text(4, G.filtersY, modLabel)
  local wmod = textWidth(modLabel)
  G.modHotspot = { x=4, y=G.filtersY, w=wmod, h=1 }

  gui.drawFrame(G.listBounds.x-2,  G.listBounds.y-2,  G.listBounds.w+4,  G.listBounds.h+4,  "Доступно к крафту", gui.colors["border"])
  gui.drawFrame(G.infoBounds.x-2,  G.infoBounds.y-2,  G.infoBounds.w+4,  G.infoBounds.h+4,  "Информация",        gui.colors["border"])

  -- нижняя кнопка
  gui.text(G.btnReload.x, G.btnReload.y, G.btnReload.label)
  G.btnReload.w = textWidth(G.btnReload.label)
end

-- список + пагинация
function G.render_list(cpuSummary)
  local x,y,w,h = G.listBounds.x, G.listBounds.y, G.listBounds.w, G.listBounds.h
  clearRect(x,y-1,w,h+1)
  G.rowMap = {}

  local src = G.craftables or {}
  local per = h
  local pages = math.max(1, math.ceil(#src / per))
  if G.listPage > pages then G.listPage = pages end
  if G.listPage < 1 then G.listPage = 1 end
  local page = G.listPage
  local start = (page-1)*per + 1
  local finish = math.min(#src, start + per - 1)

  local nav = string.format("&7Стр:&f %d/%d  &8[<]  [>]", page, pages)
  gui.text(x, y-1, nav)
  G.listPrev = { x = x + 12, y = y-1, w = 3, h = 1 }
  G.listNext = { x = x + 17, y = y-1, w = 3, h = 1 }

  for i=start,finish do
    local row = src[i]
    local line = row.label or "<?>"
    local maxChars = w - 2
    line = ucut(line, maxChars)
    local yy = y + (i-start)
    gui.text(x, yy, "&f" .. line)
    G.rowMap[yy] = row
  end

  clearRect(x, y+h, w, 1)
  local cpuText = ""
  if cpuSummary then
    cpuText = string.format("  &8CPU:&7 %d всего,&e %d заняты", cpuSummary.total or 0, cpuSummary.busy or 0)
  end
  gui.text(x, y+h, string.format("&7Найдено: &b%d%s", #G.craftables, cpuText))
end

function G.render_info(info)
  local x,y,w,h = G.infoBounds.x, G.infoBounds.y, G.infoBounds.w, G.infoBounds.h
  clearRect(x,y,w,h)
  if not info or not info.ok then
    gui.text(x, y, "&7Нет данных.")
    return
  end
  local L = {
    "&fПредмет:&b " .. (info.label or "<??>"),
    "&7В сети (шт): &b" .. tostring(info.inNetwork or 0),
    "&7Крафтабельный: &b" .. ((info.craftable and "да") or "нет"),
    "&7Название (id): &8" .. tostring(info.name or "-"),
    "&7Damage: &8" .. tostring(info.damage or "-"),
  }
  if info.status then table.insert(L, 2, "&aСтатус: &f" .. tostring(info.status)) end
  for i=1,#L do gui.text(x, y+i-1, L[i]) end
end

-- модалка крафта
function G.open_dialog(craft_row)
  G.dialog.visible = true
  G.dialog.item = craft_row
  G.dialog.qty = "1"
end
function G.close_dialog() G.dialog.visible=false; G.dialog.item=nil end

function G.render_dialog()
  if not G.dialog.visible or not G.dialog.item then return end
  local W,H = 48,10
  local x,y = getCenter(W,H)
  gui.drawFrame(x,y,W,H,"Запуск крафта", gui.colors["border"])
  local label = G.dialog.item.label or "<?>"
  gui.text(x+2, y+2, "&fПредмет: &b" .. label)

  local ibw = 12
  G.dialog.inputBox = {x=x+2, y=y+4, w=ibw, h=1}
  clearRect(G.dialog.inputBox.x, G.dialog.inputBox.y, ibw, 1)
  gui.text(G.dialog.inputBox.x, G.dialog.inputBox.y, "&f" .. (G.dialog.qty or "1"))

  local by = y + H - 3
  local okLbl, cancelLbl = "&a[Запуск]", "&c[Отмена]"
  local bx2 = x + W - textWidth(cancelLbl) - 2
  local bx1 = bx2 - textWidth(okLbl) - 2
  G.dialog.okBtn     = {x=bx1, y=by, w=textWidth(okLbl),     h=1}
  G.dialog.cancelBtn = {x=bx2, y=by, w=textWidth(cancelLbl), h=1}
  gui.text(G.dialog.okBtn.x,     by, okLbl)
  gui.text(G.dialog.cancelBtn.x, by, cancelLbl)
end

-- модалка заданий
function G.open_jobs(jobs)
  G.jobsDialog.visible = true
  G.jobsDialog.jobs = jobs or {}
  G.jobsDialog.cancelHotspots = {}
end
function G.close_jobs()
  G.jobsDialog.visible = false
  G.jobsDialog.jobs = {}
  G.jobsDialog.cancelHotspots = {}
end

function G.render_jobs()
  if not G.jobsDialog.visible then return end
  local W = 68
  local H = math.max(6, math.min(20, 4 + #G.jobsDialog.jobs))
  local x,y = getCenter(W,H)
  gui.drawFrame(x,y,W,H,"Активные задания", gui.colors["border"])

  local closeLbl = "&c[Закрыть]"
  local cw = textWidth(closeLbl)
  G.jobsDialog.closeBtn = { x = x + W - cw - 2, y = y, w = cw, h = 1 }
  gui.text(G.jobsDialog.closeBtn.x, y, closeLbl)

  local rowY = y+2
  if #G.jobsDialog.jobs == 0 then
    gui.text(x+2, rowY, "&7Нет активных заданий или функция недоступна.")
    return
  end
  for i,job in ipairs(G.jobsDialog.jobs) do
    local label = tostring(job.label or job.name or ("Job "..i))
    local maxChars = W - 18
    label = ucut(label, maxChars)
    gui.text(x+2, rowY, string.format("&f%2d.&b %s", i, label))
    local btnLbl = "&c[Отменить]"
    local bw = textWidth(btnLbl)
    local bx = x + W - bw - 2
    local btn = { x=bx, y=rowY, w=bw, h=1, id=job.id or i }
    gui.text(bx, rowY, btnLbl)
    table.insert(G.jobsDialog.cancelHotspots, btn)
    rowY = rowY + 1
  end
end

-- модалка выбора модов
local function buildModsDialog()
  G.modsDialog.items = G.allMods or {}
  if G.modsDialog.page < 1 then G.modsDialog.page = 1 end
end

function G.open_mods()
  buildModsDialog()
  G.modsDialog.visible = true
end
function G.close_mods() G.modsDialog.visible=false end

function G.render_mods()
  if not G.modsDialog.visible then return end
  local items = G.modsDialog.items or {}
  local per   = G.modsDialog.perPage
  local pages = math.max(1, math.ceil(#items / per))
  if G.modsDialog.page > pages then G.modsDialog.page = pages end
  local page  = G.modsDialog.page

  local W = 54
  local H = math.max(10, math.min(28, 7 + per))
  local x,y = getCenter(W,H)
  gui.drawFrame(x,y,W,H,"Фильтр по модам", gui.colors["border"])

  local nav = ("&7Страница: &f%d/%d  &8[<]  [>]"):format(page, pages)
  gui.text(x+2, y, nav)
  G.modsDialog.btnPrev = { x=x+2 + textWidth("&7Страница: &f"..page.."/"..pages.."  &8"), y=y, w=textWidth("[<]"), h=1 }
  G.modsDialog.btnNext = { x=G.modsDialog.btnPrev.x + textWidth("[<]  "), y=y, w=textWidth("[>]"), h=1 }

  local start = (page-1)*per + 1
  local finish = math.min(#items, start + per - 1)

  local rowY = y+2
  G.modsDialog.toggleMap = {}
  for i=start,finish do
    local mod = items[i]
    local state = (not G.modFilter.all and G.modFilter.selected[mod]) and "x" or " "
    local line = string.format("&f[%s] &b%s", state, mod)
    gui.text(x+2, rowY, line)
    local w = 2 + textWidth(line)
    local hs = { x=x+2, y=rowY, w=w, h=1, mod=mod }
    table.insert(G.modsDialog.toggleMap, hs)
    rowY = rowY + 1
  end

  local allLbl, noneLbl = "&e[Выбрать все]", "&7[Снять выбор]"
  local bw1, bw2 = textWidth(allLbl), textWidth(noneLbl)
  gui.text(x+2, y+H-3, allLbl)
  gui.text(x+2 + bw1 + 2, y+H-3, noneLbl)
  G.modsDialog.btnAll  = { x=x+2, y=y+H-3, w=bw1, h=1 }
  G.modsDialog.btnNone = { x=x+2 + bw1 + 2, y=y+H-3, w=bw2, h=1 }

  local applyLbl, cancelLbl = "&a[Применить]", "&c[Отмена]"
  local bwA, bwC = textWidth(applyLbl), textWidth(cancelLbl)
  local by = y + H - 2
  local bx2 = x + W - bwC - 2
  local bx1 = bx2 - bwA - 2
  G.modsDialog.applyBtn  = { x=bx1, y=by, w=bwA, h=1 }
  G.modsDialog.cancelBtn = { x=bx2, y=by, w=bwC, h=1 }
  gui.text(bx1, by, applyLbl)
  gui.text(bx2, by, cancelLbl)
end

-- LOADER (используется в main по месту)
G.loader = { visible=false, title="Загрузка…", done=0, total=0, label="" }
function G.open_loader(title) G.loader.visible=true; G.loader.title=title or "Загрузка…"; G.loader.done, G.loader.total, G.loader.label = 0,0,"" end
function G.update_loader(done,total,label) if G.loader.visible then G.loader.done=tonumber(done) or 0; G.loader.total=tonumber(total) or 0; G.loader.label=tostring(label or "") end end
function G.close_loader() G.loader.visible=false end
local function drawProgressBar(x,y,w,ratio) ratio = math.max(0, math.min(1, ratio or 0)); local full = math.floor(w * ratio); gui.text(x, y, "[" .. string.rep("=", full) .. string.rep(" ", w - full) .. "]") end
function G.render_loader()
  if not G.loader.visible then return end
  local W, H = 60, 7
  local x,y = getCenter(W,H)
  gui.drawFrame(x,y,W,H, stripAmp(G.loader.title), gui.colors["border"])
  local percent = 0
  if (G.loader.total or 0) > 0 then percent = G.loader.done / G.loader.total end
  gui.text(x+2, y+2, "&7Статус: &f"..ucut(G.loader.label or "", W-12))
  drawProgressBar(x+2, y+4, W-4, percent)
  gui.text(x+2, y+5, ("&8%3d%%  &7(%d/%d)"):format(math.floor(percent*100), G.loader.done or 0, G.loader.total or 0))
end

-- ===== обработчики =====
function G.handle_touch(screen, tx, ty)
  -- нижняя кнопка
  if pointIn(tx,ty,G.btnReload) then return "reload_cache" end

  -- верхние кнопки
  if pointIn(tx,ty,G.btnJobs) then return "open_jobs" end
  if pointIn(tx,ty,G.btnStop) then return "open_jobs" end

  -- навигация списка
  if G.listPrev and pointIn(tx,ty,G.listPrev) then G.listPage = math.max(1, G.listPage-1); return "search_change" end
  if G.listNext and pointIn(tx,ty,G.listNext) then G.listPage = G.listPage+1; return "search_change" end

  -- модалка заданий
  if G.jobsDialog.visible then
    if pointIn(tx,ty,G.jobsDialog.closeBtn) then
      G.close_jobs(); return "jobs_close"
    end
    for _,btn in ipairs(G.jobsDialog.cancelHotspots or {}) do
      if pointIn(tx,ty,btn) then return { action="job_cancel", id=btn.id } end
    end
    G.close_jobs(); return "jobs_close"
  end

  -- модалка крафта
  if G.dialog.visible then
    if pointIn(tx, ty, G.dialog.okBtn) then return "dialog_ok"
    elseif pointIn(tx, ty, G.dialog.cancelBtn) then G.close_dialog(); return "dialog_cancel"
    elseif pointIn(tx, ty, G.dialog.inputBox) then return "dialog_focus_input"
    else G.close_dialog(); return "dialog_close" end
  end

  -- модалка модов
  if G.modsDialog.visible then
    if pointIn(tx,ty,G.modsDialog.btnPrev) then G.modsDialog.page = math.max(1, G.modsDialog.page - 1); return "mods_toggle" end
    if pointIn(tx,ty,G.modsDialog.btnNext) then
      local pages = math.max(1, math.ceil(#(G.modsDialog.items or {}) / G.modsDialog.perPage))
      G.modsDialog.page = math.min(pages, G.modsDialog.page + 1); return "mods_toggle"
    end
    if pointIn(tx,ty,G.modsDialog.btnAll)  then G.modFilter.all=true;  G.modFilter.selected={}; return "mods_toggle" end
    if pointIn(tx,ty,G.modsDialog.btnNone) then G.modFilter.all=false; G.modFilter.selected={}; return "mods_toggle" end
    for _,hs in ipairs(G.modsDialog.toggleMap or {}) do
      if pointIn(tx,ty,hs) then G.modFilter.all=false; G.modFilter.selected[hs.mod] = not G.modFilter.selected[hs.mod]; return "mods_toggle" end
    end
    if pointIn(tx,ty,G.modsDialog.applyBtn)  then return "mods_apply" end
    if pointIn(tx,ty,G.modsDialog.cancelBtn) then G.close_mods(); return "mods_cancel" end
    return nil
  end

  if pointIn(tx,ty,G.modHotspot) then G.open_mods(); return "mods_open" end

  if pointIn(tx, ty, {x = G.searchBounds.x + 8, y = G.searchBounds.y, w = G.searchBounds.w - 8, h = 1}) then
    G.focusSearch = true; return "focus_search"
  else
    G.focusSearch = false
  end

  if tx >= G.listBounds.x and tx < G.listBounds.x + G.listBounds.w and
     ty >= G.listBounds.y and ty < G.listBounds.y + G.listBounds.h then
    local row = G.rowMap[ty]
    if row then G.open_dialog(row); return "open_dialog" end
  end
  return nil
end

function G.handle_key_down(ch, code)
  -- модалка заданий
  if G.jobsDialog.visible then if code == 1 then G.close_jobs(); return "jobs_close" end end
  -- модалка модов
  if G.modsDialog.visible then
    if code == 1 then G.close_mods(); return "mods_cancel" end
    if code == 203 then G.modsDialog.page = math.max(1, G.modsDialog.page - 1); return "mods_toggle" end
    if code == 205 then
      local pages = math.max(1, math.ceil(#(G.modsDialog.items or {}) / G.modsDialog.perPage))
      G.modsDialog.page = math.min(pages, G.modsDialog.page + 1); return "mods_toggle"
    end
  end

  -- модалка крафта
  if G.dialog.visible then
    if ch and ch >= 48 and ch <= 57 then
      local base = (G.dialog.qty == "0") and "" or (G.dialog.qty or "")
      if #base < 9 then G.dialog.qty = base .. string.char(ch) end
      if G.dialog.qty == "" then G.dialog.qty = "0" end
      return "dialog_qty_change"
    elseif code == 14 then
      if #G.dialog.qty > 1 then G.dialog.qty = G.dialog.qty:sub(1, -2) else G.dialog.qty = "1" end
      return "dialog_qty_change"
    elseif code == 28 then
      return "dialog_ok"
    elseif code == 1 then
      G.close_dialog(); return "dialog_cancel"
    end
    return nil
  end

  -- навигация страниц списка, когда не фокус в поиске
  if not G.focusSearch and not G.modsDialog.visible and not G.jobsDialog.visible then
    if code == 203 then G.listPage = math.max(1, G.listPage-1); return "search_change" end
    if code == 205 then G.listPage = G.listPage+1; return "search_change" end
  end

  -- ввод в поиск (ЮНИКОД)
  if G.focusSearch then
    if ch and ch >= 32 then
      G.searchText = G.searchText .. unicode.char(ch); return "search_change"
    elseif code == 14 then
      if unicode.len(G.searchText) > 0 then
        G.searchText = unicode.sub(G.searchText, 1, unicode.len(G.searchText)-1); return "search_change"
      end
    elseif code == 28 then
      return "search_submit"
    elseif code == 1 then
      G.focusSearch = false; return "search_blur"
    end
  end

  return nil
end

return G

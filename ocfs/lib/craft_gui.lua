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

-- список всех модов приходит извне
G.allMods      = {}   -- массив строк

-- фильтр по модам (мультивыбор)
G.modFilter = {
  selected = {},     -- set: mod -> true
  all      = false,  -- если true — игнорировать selected
}

-- верхние кнопки
G.btnStop  = { x = 116-8,  y = 2, w=8,  h=1, label = "[Стоп]" }
G.btnJobs  = { x = 116-18, y = 2, w=10, h=1, label = "[Задания]" }

-- модалки
G.dialog     = { visible=false, item=nil, qty="1", okBtn=nil, cancelBtn=nil, inputBox=nil }
G.jobsDialog = { visible=false, jobs={}, closeBtn=nil, cancelHotspots={} }
G.modsDialog = { visible=false, items={}, applyBtn=nil, cancelBtn=nil, toggleMap={} }
G.loader = { visible=false, title="Загрузка…", done=0, total=0, label="" }

-- ===== helpers =====
-- ========== ЛОАДЕР (плашка ожидания с прогрессом) ==========
G.loader = { visible=false, title="Загрузка…", done=0, total=0, label="" }

function G.open_loader(title)
  G.loader.visible = true
  G.loader.title   = title or "Загрузка…"
  G.loader.done, G.loader.total, G.loader.label = 0, 0, ""
end

function G.update_loader(done, total, label)
  if not G.loader.visible then return end
  G.loader.done  = tonumber(done) or 0
  G.loader.total = tonumber(total) or 0
  G.loader.label = tostring(label or "")
end

function G.close_loader()
  G.loader.visible = false
end

local function drawProgressBar(x,y,w,ratio)
  ratio = math.max(0, math.min(1, ratio or 0))
  local full = math.floor(w * ratio)
  gui.text(x, y, "[" .. string.rep("=", full) .. string.rep(" ", w - full) .. "]")
end

function G.render_loader()
  if not G.loader.visible then return end
  local W, H = 60, 7
  local x,y = (centerBox(W,H))
  gui.drawFrame(x,y,W,H, stripAmp(G.loader.title), gui.colors["border"])
  local percent = 0
  if (G.loader.total or 0) > 0 then
    percent = G.loader.done / G.loader.total
  end
  gui.text(x+2, y+2, "&7Статус: &f"..ucut(G.loader.label or "", W-12))
  drawProgressBar(x+2, y+4, W-4, percent)
  gui.text(x+2, y+5, ("&8%3d%%  &7(%d/%d)"):format(math.floor(percent*100), G.loader.done or 0, G.loader.total or 0))
end


local function clearRect(x,y,w,h)
  for i=0,h-1 do gui.text(x, y+i, string.rep(" ", w)) end
end
local function centerBox(W,H)
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
  -- по умолчанию ничего не выбрано; пользователь обязан выбрать
  G.modFilter.selected = {}
  G.modFilter.all = false
end
function G.get_selected_mods_set()
  if G.modFilter.all then return nil end -- nil = без фильтра (все)
  local s = G.modFilter.selected or {}
  local has = false
  for _,__ in pairs(s) do has = true break end
  if not has then return {} end
  return s
end

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

  -- краткое резюме выбранных модов
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
    if n == 0 then
      modSummary = "—"
    elseif n <= 2 then
      modSummary = table.concat(selectedList, ", ")
    else
      modSummary = ("Выбрано: %d"):format(n)
    end
  end
  local modLabel = "&e[Моды: "..modSummary.."]"
  gui.text(4, G.filtersY, modLabel)
  local wmod = textWidth(modLabel)
  G.modHotspot = { x=4, y=G.filtersY, w=wmod, h=1 }

  gui.drawFrame(G.listBounds.x-2,  G.listBounds.y-2,  G.listBounds.w+4,  G.listBounds.h+4,  "Доступно к крафту", gui.colors["border"])
  gui.drawFrame(G.infoBounds.x-2,  G.infoBounds.y-2,  G.infoBounds.w+4,  G.infoBounds.h+4,  "Информация",        gui.colors["border"])
end


function G.render_list(cpuSummary)
  local x,y,w,h = G.listBounds.x, G.listBounds.y, G.listBounds.w, G.listBounds.h
  clearRect(x,y,w,h)
  G.rowMap = {}

  local src = G.craftables or {}
  local shown = math.min(#src, h)
  for i = 1, shown do
    local line = src[i].label or "<?>"
    local maxChars = w - 2
    line = ucut(line, maxChars)
    gui.text(x, y + (i-1), "&f" .. line)
    G.rowMap[y + (i-1)] = src[i]
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
  for i=1,#L do gui.text(x, y+i-1, L[i]) end
end

-- ===== модалка запуска крафта =====
function G.open_dialog(craft_row)
  G.dialog.visible = true
  G.dialog.item = craft_row
  G.dialog.qty = "1"
end
function G.close_dialog() G.dialog.visible=false; G.dialog.item=nil end

function G.render_dialog()
  if not G.dialog.visible or not G.dialog.item then return end
  local W,H = 48,10
  local x,y = centerBox(W,H)
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

-- ===== модалка активных заданий =====
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
  local x,y = centerBox(W,H)
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

-- ===== модалка выбора модов =====
local function buildModsDialog()
  G.modsDialog.items = {}
  G.modsDialog.toggleMap = {}
  -- список модов из всей сети
  for _,mod in ipairs(G.allMods or {}) do
    table.insert(G.modsDialog.items, { mod=mod, title=mod })
  end
  -- служебные пункты
  table.insert(G.modsDialog.items, { mod="__ALL__",   title="Выбрать все" })
  table.insert(G.modsDialog.items, { mod="__NONE__",  title="Снять выбор" })
end

function G.open_mods()
  buildModsDialog()
  G.modsDialog.visible = true
end
function G.close_mods() G.modsDialog.visible=false end

function G.render_mods()
  if not G.modsDialog.visible then return end
  local items = G.modsDialog.items or {}
  local W = 44
  local H = math.max(8, math.min(26, 5 + #items))
  local x,y = centerBox(W,H)
  gui.drawFrame(x,y,W,H,"Фильтр по модам", gui.colors["border"])

  local rowY = y+2
  G.modsDialog.toggleMap = {}
  for i,it in ipairs(items) do
    local state
    if it.mod == "__ALL__" then
      state = (G.modFilter.all or false) and "x" or " "
    elseif it.mod == "__NONE__" then
      state = " "
    else
      state = (not G.modFilter.all and G.modFilter.selected[it.mod]) and "x" or " "
    end
    local line = string.format("&f[%s] &b%s", state, it.title)
    gui.text(x+2, rowY, line)
    local w = 2 + textWidth(line)
    local hs = { x=x+2, y=rowY, w=w, h=1, mod=it.mod }
    table.insert(G.modsDialog.toggleMap, hs)
    rowY = rowY + 1
  end

  local applyLbl, cancelLbl = "&a[Применить]", "&c[Отмена]"
  local bw1, bw2 = textWidth(applyLbl), textWidth(cancelLbl)
  local by = y + H - 2
  local bx2 = x + W - bw2 - 2
  local bx1 = bx2 - bw1 - 2
  G.modsDialog.applyBtn  = { x=bx1, y=by, w=bw1, h=1 }
  G.modsDialog.cancelBtn = { x=bx2, y=by, w=bw2, h=1 }
  gui.text(bx1, by, applyLbl)
  gui.text(bx2, by, cancelLbl)
end

-- ===== обработчики событий =====
function G.handle_touch(screen, tx, ty)
  -- верхние кнопки
  if pointIn(tx,ty,G.btnJobs) then return "open_jobs" end
  if pointIn(tx,ty,G.btnStop) then return "open_jobs" end

  -- модалка заданий
  if G.jobsDialog.visible then
    if pointIn(tx,ty,G.jobsDialog.closeBtn) then
      G.close_jobs()
      return "jobs_close"
    end
    for _,btn in ipairs(G.jobsDialog.cancelHotspots or {}) do
      if pointIn(tx,ty,btn) then
        return { action="job_cancel", id=btn.id }
      end
    end
    G.close_jobs()
    return "jobs_close"
  end

  -- модалка крафта
  if G.dialog.visible then
    if pointIn(tx, ty, G.dialog.okBtn) then
      return "dialog_ok"
    elseif pointIn(tx, ty, G.dialog.cancelBtn) then
      G.close_dialog()
      return "dialog_cancel"
    elseif pointIn(tx, ty, G.dialog.inputBox) then
      return "dialog_focus_input"
    else
      G.close_dialog()
      return "dialog_close"
    end
  end

  -- модалка модов
  if G.modsDialog.visible then
    if pointIn(tx,ty,G.modsDialog.applyBtn) then
      return "mods_apply"
    elseif pointIn(tx,ty,G.modsDialog.cancelBtn) then
      G.close_mods()
      return "mods_cancel"
    else
      for _,hs in ipairs(G.modsDialog.toggleMap or {}) do
        if pointIn(tx,ty,hs) then
          if hs.mod == "__ALL__" then
            -- выбрать все
            G.modFilter.all = true
            G.modFilter.selected = {}
          elseif hs.mod == "__NONE__" then
            -- снять выбор (вкл. ручной выбор)
            G.modFilter.all = false
            G.modFilter.selected = {}
          else
            -- ручной мультивыбор
            G.modFilter.all = false
            G.modFilter.selected[hs.mod] = not G.modFilter.selected[hs.mod]
          end
          return "mods_toggle"
        end
      end
      G.close_mods()
      return "mods_cancel"
    end
  end

  -- модовый хот-спот
  if pointIn(tx,ty,G.modHotspot) then
    G.open_mods()
    return "mods_open"
  end

  -- строка поиска
  if pointIn(tx, ty, {x = G.searchBounds.x + 8, y = G.searchBounds.y, w = G.searchBounds.w - 8, h = 1}) then
    G.focusSearch = true
    return "focus_search"
  else
    G.focusSearch = false
  end

  -- список
  if tx >= G.listBounds.x and tx < G.listBounds.x + G.listBounds.w and
     ty >= G.listBounds.y and ty < G.listBounds.y + G.listBounds.h then
    local row = G.rowMap[ty]
    if row then
      G.open_dialog(row)
      return "open_dialog"
    end
  end
  return nil
end

function G.handle_key_down(ch, code)
  -- модалка заданий
  if G.jobsDialog.visible then
    if code == 1 then G.close_jobs(); return "jobs_close" end
  end
  -- модалка модов
  if G.modsDialog.visible then
    if code == 1 then G.close_mods(); return "mods_cancel" end
  end

  -- модалка крафта
  if G.dialog.visible then
    if ch and ch >= 48 and ch <= 57 then
      local base = (G.dialog.qty == "0") and "" or (G.dialog.qty or "")
      if #base < 9 then
        G.dialog.qty = base .. string.char(ch)
      end
      if G.dialog.qty == "" then G.dialog.qty = "0" end
      return "dialog_qty_change"
    elseif code == 14 then -- backspace
      if #G.dialog.qty > 1 then
        G.dialog.qty = G.dialog.qty:sub(1, -2)
      else
        G.dialog.qty = "1"
      end
      return "dialog_qty_change"
    elseif code == 28 then -- Enter
      return "dialog_ok"
    elseif code == 1 then  -- Esc
      G.close_dialog()
      return "dialog_cancel"
    end
    return nil
  end

  -- ввод в поиск (ЮНИКОД)
  if G.focusSearch then
    if ch and ch >= 32 then
      G.searchText = G.searchText .. unicode.char(ch)
      return "search_change"
    elseif code == 14 then -- backspace
      if unicode.len(G.searchText) > 0 then
        G.searchText = unicode.sub(G.searchText, 1, unicode.len(G.searchText)-1)
        return "search_change"
      end
    elseif code == 28 then -- Enter
      return "search_submit"
    elseif code == 1 then -- Esc
      G.focusSearch = false
      return "search_blur"
    end
  end

  return nil
end

return G

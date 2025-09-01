-- main.lua
local component = require("component")
local event     = require("event")
local term      = require("term")
local computer  = require("computer")

local gpu       = component.isAvailable("gpu") and component.gpu or nil
local chatBox   = component.isAvailable("chat_box") and component.chat_box or nil

local gui       = require("ugui")
local model     = require("craft_model")
local view      = require("craft_gui")

local function say(msg) if chatBox then pcall(function() chatBox.say(msg) end) end

-- дефолт: только Modular Machinery: Community Edition
local DEFAULT_MM = { mmce=true, modularmachinery=true, modular_machinery=true }

local function collect_mods(list)
  local set, arr = {}, {}
  for _,it in ipairs(list or {}) do
    local m = it.mod or "unknown"
    if not set[m] then set[m]=true; arr[#arr+1]=m end
  end
  table.sort(arr)
  return arr
end

term.clear()
if gpu then pcall(function() gpu.setResolution(120,40) end) end
view.draw_shell("&d[Панель ME-крафта]")

-- применить активные фильтры модов (если нет выбора — дефолт MMCE)
local function activeWhitelist()
  if view.modFilter.all then return nil end
  local sel = view.modFilter.selected
  local has=false; for _ in pairs(sel) do has=true break end
  if has then return sel end
  return DEFAULT_MM
end

local function reload_list()
  local wl = activeWhitelist()
  view.craftables = model.get_craftables(view.searchText, wl)

  -- Остальное (если включено)
  if view.modFilter.includeOther and not view.modFilter.all then
    local all = model.get_craftables(view.searchText, nil)
    local seen = {}
    for _,it in ipairs(view.craftables) do seen[(it.name or "")..":"..tostring(it.damage)] = true end
    for _,it in ipairs(all) do
      local key = (it.name or "")..":"..tostring(it.damage)
      if not (wl and wl[it.mod or "unknown"]) and not seen[key] then
        table.insert(view.craftables, it)
      end
    end
  end

  view.modFilter.topMods = collect_mods(model.get_craftables("", nil))
  view.render_list()
  view.render_info(nil, nil)
end

local function refresh_cpu() view.render_status(model.get_cpu_summary()) end
local function refresh_info()
  local idx = view.selectedIndex
  if idx and view.craftables[idx] then
    local item = view.craftables[idx]
    view.render_info(item, model.get_item_info(item))
  else
    view.render_info(nil, nil)
  end
end

reload_list(); refresh_cpu()
local lastCpu = computer.uptime()

while true do
  if computer.uptime() - lastCpu > 1.0 then refresh_cpu(); lastCpu = computer.uptime() end

  view.render_dialog()
  view.render_jobs_dialog()
  view.render_mods_dialog()

  local ev,a1,a2,a3 = event.pull(0.1)
  if ev=="touch" then
    local action,arg = view.handle_touch(a1,a2,a3)

    if action=="open_dialog" or action=="dialog_focus_input" then
      view.render_dialog(); refresh_info()

    elseif action=="dialog_cancel" or action=="dialog_close" then
      view.draw_shell("&d[Панель ME-крафта]"); view.render_list(); refresh_info()

    elseif action=="dialog_ok" then
      local qty = tonumber(view.dialog.qty) or 1; if qty<1 then qty=1 end
      local ok, err = model.request_craft(view.dialog.item, qty)
      if ok then say("§aЗапущен крафт: §e"..(view.dialog.item.label or "<?>").." §7x§b"..qty)
      else      say("§cОшибка запуска крафта: §7"..tostring(err)) end
      view.close_dialog()
      view.draw_shell("&d[Панель ME-крафта]"); view.render_list(); refresh_info()

    elseif action=="open_jobs" then
      view.open_jobs_dialog(model.get_jobs()); view.render_jobs_dialog()

    elseif action=="jobs_close" then
      view.draw_shell("&d[Панель ME-крафта]"); view.render_list(); refresh_info()

    elseif action=="jobs_cancel" then
      local id = arg
      local ok = model.cancel_job(id)
      if ok then say("§cОтменено задание #"..tostring(id)) else say("§cНе удалось отменить #"..tostring(id)) end
      view.open_jobs_dialog(model.get_jobs()); view.render_jobs_dialog()

    elseif action=="stop_all" then
      local jobs = model.get_jobs() or {}
      local n=0
      for _,j in ipairs(jobs) do local id=j.id or j.ID; if id and model.cancel_job(id) then n=n+1 end end
      say("§cОстановлено заданий: §e"..tostring(n))
      view.draw_shell("&d[Панель ME-крафта]"); reload_list(); refresh_info()

    elseif action=="focus_search" then
      view.draw_shell("&d[Панель ME-крафта]"); view.render_list(); refresh_info()

    elseif action=="open_mods" then
      view.open_mods_dialog(view.modFilter.topMods, view.modFilter.selected, view.modFilter.includeOther, view.modFilter.all)
      view.render_mods_dialog()

    elseif action=="mods_toggle" then
      view.render_mods_dialog()

    elseif action=="mods_apply" or action=="mods_cancel" then
      view.draw_shell("&d[Панель ME-крафта]"); reload_list(); refresh_info()
    end

  elseif ev=="key_down" then
    local action = view.handle_key_down(a2,a3)
    if action=="search_change" then
      view.draw_shell("&d[Панель ME-крафта]"); view.render_list(); refresh_info()
    elseif action=="search_submit" then
      reload_list(); view.draw_shell("&d[Панель ME-крафта]"); view.render_list(); refresh_info()
    elseif action=="dialog_qty_change" then
      view.render_dialog()
    elseif action=="dialog_ok" then
      local qty = tonumber(view.dialog.qty) or 1; if qty<1 then qty=1 end
      local ok, err = model.request_craft(view.dialog.item, qty)
      if ok then say("§aЗапущен крафт: §e"..(view.dialog.item.label or "<?>").." §7x§b"..qty)
      else      say("§cОшибка запуска крафта: §7"..tostring(err)) end
      view.close_dialog()
      view.draw_shell("&d[Панель ME-крафта]"); view.render_list(); refresh_info()
    elseif action=="dialog_cancel" then
      view.draw_shell("&d[Панель ME-крафта]"); view.render_list(); refresh_info()
    end

  elseif ev=="interrupted" then
    break
  end
end
end

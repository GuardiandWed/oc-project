-- /home/main.lua
local component = require("component")
local event     = require("event")
local term      = require("term")

local gpu       = component.isAvailable("gpu") and component.gpu or nil
local chatBox   = component.isAvailable("chat_box") and component.chat_box or nil

local view      = require("craft_gui")
local model     = require("craft_model")

local function say(msg)
  if chatBox then pcall(function() chatBox.say(msg) end) end
end

term.clear()
if gpu then
  pcall(function() gpu.setResolution(120, 40) end)
  pcall(function() gpu.setForeground(0xFFFFFF) end)
end

view.draw_shell("&d[Панель ME-крафта]")

local Chat = require("chatcmd")

-- создаём чат-обработчик
local bot = Chat.new{
  prefix = "@",
  name   = "Оператор",
  admins = {"HauseMasters"} -- твой ник
}

bot:start()

-- 1) моды из сети (быстро, 1 проход)
model.rebuild_cache()
view.set_mods(model.get_all_mods())

-- 2) предзагрузка ВСЕХ крафтов в кеш с прогрессом
view.open_loader("Подготовка списка крафтов…")
model.build_craft_cache(function(done, total, label)
  -- callback прорисовки: обновляем плашку ожидания
  view.update_loader(done, total, label or "")
  view.render_loader()
end)
view.close_loader()

-- 3) сразу требуем выбор модов
view.open_mods()
view.render_mods()

local firstRun = true

view.open_loader("Применение фильтра…")
view.update_loader(1,1,"")
view.render_loader()
os.sleep(0.05)
view.close_loader()

local function reload_list()
  local modSet = view.get_selected_mods_set()  -- { mod -> true }
  local search = view.searchText
  -- фильтра-плашки убраны, оставляем только поиск и моды
  view.craftables = model.get_craftables(search, { modSet = modSet })
  local cpu = model.get_cpu_summary()
  view.render_list(cpu)
end

local function redraw_modals()
  view.render_dialog()
  view.render_jobs()
  view.render_mods()
  view.render_loader() -- NEW: поверх всего
end


local function draw_info_for(row)
  local info = model.get_item_info(row or {})
  view.render_info(info)
end

-- пока моды не выбраны — не грузим список
draw_info_for(nil)

while true do
  redraw_modals()
  local ev, a1, a2, a3 = event.pull(0.1)

  if ev == "touch" then
    local action = view.handle_touch(a1, a2, a3)

    if action == "open_dialog" or action == "dialog_focus_input" then
      draw_info_for(view.dialog.item)
      view.render_dialog()

    elseif action == "focus_search" or action == "search_change" or action == "search_submit" then
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()

    elseif action == "dialog_cancel" or action == "dialog_close" then
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()
      draw_info_for(nil)

    elseif action == "dialog_ok" then
      local qty = tonumber(view.dialog.qty) or 1
      local ok, err = model.request_craft(view.dialog.item, qty)
      if ok then
        say("§aЗапущен крафт: §e" .. tostring(view.dialog.item.label or "<?>") .. " §7x§b" .. tostring(qty))
      else
        say("§cОшибка запуска крафта: §7" .. tostring(err))
      end
      view.close_dialog()
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()
      draw_info_for(nil)

    elseif action == "open_jobs" then
      local jobs = model.get_jobs()
      view.open_jobs(jobs)
      view.render_jobs()

    elseif type(action)=="table" and action.action=="job_cancel" then
      local ok, err = model.cancel_job(action.id)
      if ok then say("§eЗадание отменено: §7"..tostring(action.id))
      else       say("§cНе удалось отменить: §7"..tostring(err)) end
      local jobs = model.get_jobs()
      view.open_jobs(jobs)
      view.render_jobs()

    elseif action == "jobs_close" then
      view.draw_shell("&d[Панель ME-крафта]")
      if not firstRun then reload_list() end

    elseif action == "mods_open" or action == "mods_toggle" then
      view.render_mods()

    elseif action == "mods_cancel" then
      -- во время первичного запуска отменять нельзя — требуем выбор
      if firstRun then
        view.open_mods()
        view.render_mods()
      else
        view.draw_shell("&d[Панель ME-крафта]")
        reload_list()
      end

    elseif action == "mods_apply" then
      firstRun = false
      view.close_mods()
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()
    end

  elseif ev == "key_down" then
    local ch, code = a2, a3
    local action = view.handle_key_down(ch, code)

    if action == "search_change" or action == "search_submit" then
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()

    elseif action == "dialog_qty_change" then
      view.render_dialog()

    elseif action == "dialog_ok" then
      local qty = tonumber(view.dialog.qty) or 1
      local ok, err = model.request_craft(view.dialog.item, qty)
      if ok then
        say("§aЗапущен крафт: §e" .. tostring(view.dialog.item.label or "<?>") .. " §7x§b" .. tostring(qty))
      else
        say("§cОшибка запуска крафта: §7" .. tostring(err))
      end
      view.close_dialog()
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()
      draw_info_for(nil)

    elseif action == "dialog_cancel" then
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()
      draw_info_for(nil)

    elseif action == "jobs_close" or action == "mods_cancel" then
      if not firstRun then
        view.draw_shell("&d[Панель ME-крафта]")
        reload_list()
      else
        view.open_mods()
        view.render_mods()
      end
    end

  elseif ev == "interrupted" then
    break
  end
end

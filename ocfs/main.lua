-- /home/main.lua
local component = require("component")
local event     = require("event")
local term      = require("term")

local gpu       = component.isAvailable("gpu") and component.gpu or nil
local chatBox   = component.isAvailable("chat_box") and component.chat_box or nil

local gui       = require("ugui")
local model     = require("craft_model")
local view      = require("craft_gui")

local function say(msg)
  if chatBox then pcall(function() chatBox.say(msg) end) end
end

term.clear()
if gpu then
  pcall(function() gpu.setResolution(120, 40) end)
  pcall(function() gpu.setForeground(0xFFFFFF) end)
end

view.draw_shell("&d[Панель ME-крафта]")

local function reload_list()
  -- передаём фильтры в модель
  local opts = {
    exact         = view.filters.exact,
    onlyCraftable = view.filters.onlyCraftable,
    onlyStored    = view.filters.onlyStored,
  }
  view.craftables = model.get_craftables(view.searchText, opts)
  local cpu = model.get_cpu_summary()
  view.render_list(cpu)
end

local function redraw_modals()
  view.render_dialog()
  view.render_jobs()
  view.render_mods()
end

local function draw_info_for(row)
  local info = model.get_item_info(row or {})
  view.render_info(info)
end

reload_list()
draw_info_for(nil)

while true do
  redraw_modals()
  local ev, a1, a2, a3 = event.pull(0.1)

  if ev == "touch" then
    local action = view.handle_touch(a1, a2, a3)

    if action == "open_dialog" or action == "dialog_focus_input" then
      draw_info_for(view.dialog.item)
      view.render_dialog()

    elseif action == "filters_change" or action == "focus_search" then
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
      reload_list()

    elseif action == "mods_open" or action == "mods_toggle" then
      view.render_mods()

    elseif action == "mods_cancel" then
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()

    elseif action == "mods_apply" then
      view.close_mods()
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()
    end

  elseif ev == "key_down" then
    local ch, code = a2, a3
    local action = view.handle_key_down(ch, code)

    if action == "search_change" then
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()
    elseif action == "search_submit" then
      reload_list()
      view.draw_shell("&d[Панель ME-крафта]")

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
      view.draw_shell("&d[Панель ME-крафта]")
      reload_list()
    end

  elseif ev == "interrupted" then
    break
  end
end

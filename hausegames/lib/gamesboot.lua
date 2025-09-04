-- /home/lib/gamesboot.lua
-- Чтение списка игр и (позже) запуск.

local fs   = require("filesystem")
local comp = require("computer")
local ser  = require("serialization")

local M = {}

local function file_exists(p) return p and fs.exists(p) and not fs.isDirectory(p) end

local function read_json(path)
  if not file_exists(path) then return nil end
  local f = io.open(path, "rb"); if not f then return nil end
  local data = f:read("*a"); f:close()
  -- простой JSON: позволим Lua-таблицу через serialization (если JSON нет)
  local ok, val = pcall(require, "json")
  if ok and val and val.decode then return val.decode(data) end
  -- запасной вариант: массив из Lua-формата
  local ok2, tbl = pcall(ser.unserialize, data)
  if ok2 then return tbl end
  return nil
end

local function fmt_hm(sec)
  sec = tonumber(sec or 0) or 0
  local h = math.floor(sec/3600)
  local m = math.floor((sec%3600)/60)
  return string.format("%02d:%02d", h, m)
end

function M.list_games()
  local list = read_json("/home/games/games_list.json")
  if not list or type(list) ~= "table" or #list == 0 then
    -- демо
    return {
      { name="Snake",    created="2025-08-31", played_h="00:00" },
      { name="Tetris",   created="2025-08-25", played_h="02:14" },
      { name="2048",     created="2025-08-12", played_h="00:47" },
      { name="Pong",     created="2025-07-08", played_h="01:05" },
      { name="Mines",    created="2025-06-21", played_h="--"    },
      { name="Breakout", created="2025-06-01", played_h="03:33" },
    }
  end
  -- нормализуем поля played_seconds -> played_h
  for _,g in ipairs(list) do
    if g.played_seconds and not g.played_h then
      g.played_h = fmt_hm(g.played_seconds)
    end
  end
  return list
end

function M.run(gameName)
  -- позже: dofile("/home/games/"..gameName..".lua")
  comp.beep(1200, 0.08)
end

return M

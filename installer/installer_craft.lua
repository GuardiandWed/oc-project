-- OCFS Installer (OpenComputers, std libs)
-- UI/logic by ChatGPT for your project
-- Помещай этот файл куда угодно (например, /home/installer.lua) и запускай.
-- Он скачает всё из GitHub: ocfs/lib/** -> /lib/**, остальное -> в текущую папку.

------------------------------------ CONFIG ------------------------------------
-- URL должен указывать ИМЕННО на папку ocfs/ в raw:
-- Пример: "https://raw.githubusercontent.com/<user>/<repo>/refs/heads/main/ocfs/"
local REPOSITORY = "https://raw.githubusercontent.com/GuardiandWed/oc-project/refs/heads/main/hausegames/"

-- Если manifest.txt в репозитории отсутствует, используем этот дефолтный список:
local DEFAULT_FILES = {
  "hausegames.lua",
  "lib/gamesboot.lua",
  "lib/rcui.lua",
  "games/games_list.json",
  "data/boot_log.txt",
  "lib/chatcmd.lua",
}

local APP_TITLE   = "HauseGames — Installer"
local REBOOT_AFTER = false   -- при желании можно включить авт ребут

-------------------------------------------------------------------------------
local component = require("component")
local gpu       = component.gpu
local term      = require("term")
local event     = require("event")
local unicode   = require("unicode")
local shell     = require("shell")
local fs        = require("filesystem")
local computer  = require("computer")

-- Проверки окружения
if not component.isAvailable("gpu") then error("GPU required") end
if not component.isAvailable("internet") then
  error("Internet card required (no component 'internet').")
end

-- Цвета
local COL_BG     = 0x0A0F0A
local COL_FRAME  = 0x0F1F0F
local COL_TEXT   = 0xDDFFDD
local COL_DIM    = 0x99CC99
local COL_WARN   = 0xFFD37F
local COL_ERR    = 0xFF6B6B
local COL_OK     = 0x7CFF7C
local COL_BARBG  = 0x123312
local COL_BAR    = 0x22FF88

-- Экран/состояние
local sw, sh = gpu.getResolution()
local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()

local function safeSetBG(c) gpu.setBackground(c) end
local function safeSetFG(c) gpu.setForeground(c) end
local function fill(x,y,w,h,bg) safeSetBG(bg); gpu.fill(x,y,w,h," ") end
local function text(x,y,str,fg) if fg then safeSetFG(fg) end; gpu.set(x,y,str) end
local function centerX(w) return math.max(1, math.floor((sw - w)/2)+1) end
local function centerY(h) return math.max(1, math.floor((sh - h)/2)+1) end

local function frame(x,y,w,h)
  safeSetFG(COL_DIM)
  gpu.set(x,y,       "┌"..string.rep("─",math.max(0,w-2)).."┐")
  for i=1,math.max(0,h-2) do gpu.set(x,y+i,"│"..string.rep(" ",math.max(0,w-2)).."│") end
  gpu.set(x,y+h-1,   "└"..string.rep("─",math.max(0,w-2)).."┘")
end

local function progressBar(x,y,w,ratio)
  local full = math.max(0, math.min(w, math.floor(w*ratio)))
  safeSetBG(COL_BARBG); gpu.fill(x,y,w,1," ")
  safeSetBG(COL_BAR);   gpu.fill(x,y,full,1," ")
  safeSetBG(COL_BG)
end

local function shorten(str,maxLen)
  if unicode.len(str) <= maxLen then return str end
  return unicode.sub(str,1,maxLen-3).."..."
end

-- Адаптивная верстка под маленькие экраны
local W, H = 70, 22
if sw < W+2 then W = math.max(40, sw-2) end
if sh < H+2 then H = math.max(18, sh-2) end
local X, Y = centerX(W), centerY(H)

local function drawChrome(appTitle)
  term.clear()
  safeSetBG(COL_BG); fill(1,1,sw,sh,COL_BG)
  fill(X,Y,W,H,COL_FRAME); frame(X,Y,W,H)
  text(X+2, Y, "┤ "..appTitle.." ├", COL_TEXT)
  text(X+2, Y+2, "Status:",   COL_DIM)
  text(X+2, Y+6, "Progress:", COL_DIM)
  text(X+2, Y+9, "Log:",      COL_DIM)
  fill(X+2, Y+7, W-4, 1, COL_BARBG)
end

local function writeStatus(msg, color)
  fill(X+2, Y+3, W-4, 2, COL_FRAME)
  text(X+2, Y+3, shorten(msg, W-6), color or COL_TEXT)
end

local logTop, logHeight = Y+10, H-11
local logLines = {}
local function log(msg, color)
  color = color or COL_TEXT
  if #logLines >= logHeight then table.remove(logLines,1) end
  table.insert(logLines, shorten(msg, W-6))
  for i=1,logHeight do
    fill(X+2, logTop+i-1, W-4, 1, COL_FRAME)
    local ln = logLines[i]
    if ln then text(X+2, logTop+i-1, ln, color) end
  end
end

local spinner = {"⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"}
local spinIdx = 1
local function tickSpinner()
  local s = spinner[spinIdx]; spinIdx = spinIdx % #spinner + 1
  text(X+W-4, Y+3, s, COL_DIM)
end

-- Утилиты путей
local function dirname(path)
  local p = path:gsub("/+$","")
  local cut = p:match("^(.*)/[^/]+$")
  return cut or ""
end

local function ensureDir(path)
  if path ~= "" and not fs.exists(path) then fs.makeDirectory(path) end
end

-- вычисляем куда сохранить: lib/** -> /lib/**, иначе в текущую папку
local function targetPathFor(rel)
  rel = rel:gsub("^/+", "")
  if rel:sub(1,4) == "lib/" then
    return "/"..rel               -- например: /lib/ugui.lua или /lib/Format/x.lua
  else
    local cwd = shell.getWorkingDirectory()
    return fs.concat("/", cwd, rel) -- /<cwd>/<rel>
  end
end

-- читаем manifest.txt, если есть
local function getFileList()
  local tmp = "/tmp/ocfs_manifest.txt"
  fs.makeDirectory("/tmp")
  -- пробуем скачать манифест
  shell.execute(string.format('wget -fq "%s" "%s"', REPOSITORY.."manifest.txt", tmp))
  if fs.exists(tmp) then
    local t = {}
    for line in io.lines(tmp) do
      line = line:gsub("\r","")
      if line ~= "" and not line:match("^#") then
        table.insert(t, line)
      end
    end
    fs.remove(tmp)
    if #t > 0 then return t end
  end
  return DEFAULT_FILES
end

local function install()
  drawChrome(APP_TITLE)
  writeStatus("Инициализация…", COL_DIM)
  log("Используем репозиторий: "..REPOSITORY, COL_DIM)

  local files = getFileList()
  local total = #files
  if total == 0 then
    writeStatus("Нет файлов для установки.", COL_ERR)
    log("Пустой список файлов.", COL_ERR)
    text(X+2, Y+H-2, "Нажми любую клавишу…", COL_TEXT)
    event.pull("key_down")
    return
  end

  local okCount, failCount = 0, 0

  for i, rel in ipairs(files) do
    local url  = REPOSITORY .. rel
    local dest = targetPathFor(rel)
    ensureDir(dirname(dest))

    local label = string.format("[%02d/%02d] %s", i, total, shorten(rel, 30))
    writeStatus("Загрузка "..label, COL_TEXT)
    log("wget "..shorten(url, 60).." -> "..dest, COL_DIM)

    local cmd = string.format('wget -fq "%s" "%s"', url, dest)
    local ok = shell.execute(cmd)
    tickSpinner()

    if ok then
      okCount = okCount + 1
      log("OK: "..rel, COL_OK)
    else
      failCount = failCount + 1
      log("ERROR: "..rel, COL_ERR)
    end

    local ratio = i/total
    progressBar(X+2, Y+7, W-4, ratio)
    text(X+2, Y+8,
      string.format("Progress: %d%%  OK:%d  Fail:%d", math.floor(ratio*100), okCount, failCount),
      COL_DIM)
  end

  if failCount == 0 then
    writeStatus("Установка завершена: все файлы ок.", COL_OK)
  else
    writeStatus("Готово с ошибками. См. лог выше.", COL_WARN)
  end

  if REBOOT_AFTER then
    for n=3,1,-1 do
      text(X+W-18, Y+H-2, ("Reboot in %d...      "):format(n), COL_TEXT)
      os.sleep(1)
    end
    shell.execute("reboot")
  else
    text(X+2, Y+H-2, "Готово. Нажми любую клавишу для выхода…", COL_TEXT)
    event.pull("key_down")
  end
end

local ok, err = pcall(install)
safeSetBG(oldBG); safeSetFG(oldFG)
if not ok then
  term.clear()
  io.stderr:write("Installer crashed: "..tostring(err).."\n")
end
